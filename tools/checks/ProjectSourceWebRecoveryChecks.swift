import Foundation
import SQLite3

@main
struct ProjectSourceWebRecoveryChecks {
  static let notice = "処理は中断されました。ソースは保持しています。必要に応じて再試行してください。自動では再開しません。"
  static var response: WebSourceHTTPDecoder.Response {
    .init(status: 200, headers: ["content-type": "text/html"],
      body: Data("<html><title>架空の出典</title><p>保存するfixture本文</p></html>".utf8))
  }
  static var fetcher: WebSourceFetcher {
    WebSourceFetcher(resolve: { _ in ["93.184.215.14"] }, transfer: { _ in response })
  }

  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    try await webPaths(root)
    for write in [false, true] {
      for change in 0..<14 { try await race(root, write: write, change: change) }
    }
    try await replacement(root)
    try await cancellation(root)
    try await rollback(root)
    try await recovery(root)
    print("ProjectSourceWebRecoveryChecks: passed (production fetch orchestration/client/text extraction/file/SQLite reopen; 28 suspended-response/write races, replacement ownership, cancellation, SQL rollback/retry, orphaned-status recovery and failed recovery save; DNS/HTTP payload and model state are fixtures, no network)")
  }

  @MainActor static func fixture(_ root: URL, _ name: String) throws -> (MemoraModel, UUID) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("\(name).sqlite"))
    let project = MemoraSpace(id: UUID(), name: "架空のWeb保存先", symbol: "folder")
    model.spaces = [project]
    var source = ProjectSource(projectID: project.id, kind: .web, title: "元のタイトル",
      originalURL: URL(string: "https://example.com/fixture")!)
    source.processingStatus = .unavailable
    precondition(model.storeProjectSource(source))
    return (model, source.id)
  }

  @MainActor static func webPaths(_ root: URL) async throws {
    let (model, id) = try fixture(root, "web-success")
    expect(await model.fetchProjectWebSource(id, fetcher: fetcher))
    let saved = model.source(id: id)!
    precondition(saved.processingStatus == .ready && saved.textCoverage == .partial && !saved.privacy.allowsCloudAI)
    precondition(saved.title == "架空の出典" && saved.metadata?["webFinalURL"] == "https://example.com/fixture")
    expect(try ProjectSourceTextReader.read(saved.extractedTextReference!).first?.text == "保存するfixture本文")
    expect(try reload(model) == model.projectSources)
    var shared = saved
    shared.id = UUID()
    precondition(model.storeProjectSource(shared))
    expect(await model.fetchProjectWebSource(id, fetcher: fetcher))
    expect(try ProjectSourceTextReader.read(shared.extractedTextReference!).first?.text == "保存するfixture本文")
    let old = model.source(id: id)!
    let offline = WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in throw WebSourceFailure.timeout })
    expect(await !model.fetchProjectWebSource(id, fetcher: offline))
    precondition(model.source(id: id)!.extractedTextReference == old.extractedTextReference && model.source(id: id)!.canProvideText)
    precondition(model.source(id: id)!.errorInformation?.contains("以前に取得した本文") == true)
    expect(try reload(model) == model.projectSources)
    let refused = WebSourceFetcher(resolve: { _ in preconditionFailure("Refused fetch resolved a host") })
    for state in 0..<4 {
      let (guarded, guardedID) = try fixture(root, "guard-\(state)")
      switch state {
      case 0: guarded.currentTeamID = "unconfigured"
      case 1: guarded.isRestoring = true
      case 2: guarded.isStoreProtected = true
      default: guarded.spaces = []
      }
      expect(await !guarded.fetchProjectWebSource(guardedID, fetcher: refused))
      precondition(guarded.projectWebFetchJobs.isEmpty && guarded.projectSourceProcessingIDs.isEmpty)
    }
  }

  @MainActor static func race(_ root: URL, write: Bool, change: Int) async throws {
    let (model, id) = try fixture(root, "race-\(write)-\(change)")
    let before = try files()
    let gate = WebRecoveryGate()
    let suspended = WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in
      if write { return response }
      return try await gate.wait()
    })
    let operation = Task { await model.fetchProjectWebSource(id, fetcher: suspended, writeText: { data in
      let reference = try await ProjectSourceFiles.shared.write(data, extension: "json")
      if write { _ = try await gate.wait() }
      return reference
    }) }
    await gate.entered()
    if write { expect(try files().subtracting(before).count == 1) }
    switch change {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "先に更新されたproject"
    case 6: model.projectSources[0].privacy.protect(.personal)
    case 7: model.projectSources[0].projectID = nil
    case 8: model.projectSources[0].title = "先に更新されたタイトル"
    case 9: model.projectSources = []
    case 10: model.projectSources[0].kind = .note
    case 11: model.projectSources[0].metadata = ["new": "変更"]
    case 12: model.projectSources[0].originalURL = URL(string: "https://example.com/replaced")!
    default: model.aiWorkspaceGeneration = UUID()
    }
    let snapshot = model.projectSources
    if (6...12).contains(change) {
      precondition(model.persistNow(snapshot, forKey: MemoraModel.StorageKey.projectSources))
    }
    let durable = try reload(model)
    gate.resume(response)
    expect(await !operation.value)
    precondition(model.projectSources == snapshot && model.projectWebFetchJobs.isEmpty && model.projectSourceProcessingIDs.isEmpty)
    expect(try reload(model) == durable && files() == before)
  }

  @MainActor static func replacement(_ root: URL) async throws {
    let (model, id) = try fixture(root, "replacement")
    let firstGate = WebRecoveryGate(), secondGate = WebRecoveryGate()
    let first = Task { await model.fetchProjectWebSource(id, fetcher: WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in try await firstGate.wait() })) }
    await firstGate.entered()
    model.cancelProjectWebFetches()
    let second = Task { await model.fetchProjectWebSource(id, fetcher: WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in try await secondGate.wait() })) }
    await secondGate.entered()
    let owner = model.projectWebFetchJobs[id]!.id
    firstGate.resume(response)
    expect(await !first.value)
    precondition(model.projectWebFetchJobs[id]?.id == owner && model.projectSourceProcessingIDs.contains(id))
    precondition(model.source(id: id)!.processingStatus == .unavailable)
    secondGate.resume(response)
    expect(await second.value)
    precondition(model.projectWebFetchJobs.isEmpty && model.projectSourceProcessingIDs.isEmpty)
    expect(try reload(model) == model.projectSources)
  }

  @MainActor static func cancellation(_ root: URL) async throws {
    let (model, id) = try fixture(root, "cancel")
    let gate = WebRecoveryGate()
    let operation = Task { await model.fetchProjectWebSource(id, fetcher: WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in try await gate.wait() })) }
    await gate.entered()
    operation.cancel()
    gate.resume(response)
    expect(await !operation.value)
    precondition(model.source(id: id)!.processingStatus == .unavailable && !model.source(id: id)!.canProvideText)
    precondition(model.source(id: id)!.errorInformation?.contains("停止") == true)
    precondition(model.projectWebFetchJobs.isEmpty && model.projectSourceProcessingIDs.isEmpty)
    expect(try reload(model) == model.projectSources)
  }

  @MainActor static func rollback(_ root: URL) async throws {
    let (model, id) = try fixture(root, "rollback")
    let original = model.projectSources
    let before = try files()
    let rejected = WebSourceFetcher(resolve: fetcher.resolve, transfer: { _ in
      try await MainActor.run { try sql("CREATE TRIGGER reject_web BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'web check'); END;", model.storeURL) }
      return response
    })
    expect(await !model.fetchProjectWebSource(id, fetcher: rejected))
    precondition(model.projectSources == original && model.persistenceFailureMessage != nil)
    expect(try reload(model) == original && files() == before)
    try sql("DROP TRIGGER reject_web;", model.storeURL)
    expect(await model.fetchProjectWebSource(id, fetcher: fetcher))
    expect(try reload(model) == model.projectSources)
  }

  @MainActor static func recovery(_ root: URL) async throws {
    let (model, _) = try fixture(root, "recovery")
    let reference = try await ProjectSourceFiles.shared.write(JSONEncoder().encode([ProjectSourceText(text: "保持する本文")]), extension: "json")
    let originalFile = try await ProjectSourceFiles.shared.write(Data("保持する原本".utf8), extension: "txt")
    let thumbnail = try await ProjectSourceFiles.shared.write(Data([0xff, 0xd8, 0xff, 0xd9]), extension: "jpg")
    let kinds: [ProjectSource.Kind] = [.youtube, .web, .pdf, .image, .document, .audio, .note]
    let states: [ProjectSource.ProcessingStatus] = [.pending, .processing, .ready, .failed, .unavailable]
    model.projectSources = kinds.flatMap { kind in states.map { state in
      var value = ProjectSource(projectID: model.spaces[0].id, kind: kind, title: "保持する名前", originalURL: URL(string: "https://example.com/kept"))
      value.processingStatus = state
      value.localFileReference = originalFile
      value.extractedTextReference = reference
      value.thumbnailReference = thumbnail
      value.textCoverage = .partial
      value.errorInformation = "以前の説明"
      value.metadata = ["youtubeTitle": "保持する動画情報", "kept": "残す"]
      value.privacy.protect(.personal)
      return value
    } }
    precondition(model.persistNow(model.projectSources, forKey: MemoraModel.StorageKey.projectSources))
    let original = model.projectSources
    let active = original.first { $0.kind == .pdf && $0.processingStatus == .processing }!.id
    model.projectSourceProcessingIDs = [active]
    var expected = original
    for index in expected.indices where expected[index].processingStatus == .processing && expected[index].id != active {
      expected[index].processingStatus = expected[index].kind == .youtube ? .unavailable : .failed
      expected[index].errorInformation = notice
    }
    let before = try files()
    precondition(model.recoverInterruptedProjectSources() && model.projectSources == expected)
    expect(try reload(model) == expected && files() == before)
    // An idempotent reconciliation performs no SQL write, even when writes fail.
    try sql("CREATE TRIGGER reject_recovery BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'recovery check'); END;", model.storeURL)
    precondition(model.recoverInterruptedProjectSources())
    model.projectSourceProcessingIDs = []
    precondition(!model.recoverInterruptedProjectSources() && model.projectSources == expected)
    expect(try reload(model) == expected && files() == before)
    try sql("DROP TRIGGER reject_recovery;", model.storeURL)
    precondition(model.recoverInterruptedProjectSources())
    expected[expected.firstIndex { $0.id == active }!].processingStatus = .failed
    expected[expected.firstIndex { $0.id == active }!].errorInformation = notice
    precondition(model.projectSources == expected)
    expect(try reload(model) == expected && files() == before)
    for state in 0..<3 {
      var orphan = original[1]
      orphan.id = UUID()
      model.projectSources = [orphan]
      if state == 0 { model.currentTeamID = "unconfigured" }
      if state == 1 { model.isRestoring = true }
      if state == 2 { model.isStoreProtected = true }
      precondition(!model.recoverInterruptedProjectSources() && model.projectSources == [orphan])
      model.currentTeamID = nil; model.isRestoring = false; model.isStoreProtected = false
    }
    expect(try files() == before)
    expect(try Data(contentsOf: ProjectSourceFiles.resolve(originalFile)!) == Data("保持する原本".utf8))
    expect(try ProjectSourceTextReader.read(reference).first?.text == "保持する本文")
  }

  static func expect(_ value: Bool) { precondition(value) }
  @MainActor static func reload(_ model: MemoraModel) throws -> [ProjectSource] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let bytes) = store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Missing source document") }
    return try JSONDecoder().decode([ProjectSource].self, from: bytes)
  }
  static func files() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path)) }
  static func sql(_ statement: String, _ url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }
}

@MainActor private final class WebRecoveryGate {
  var continuation: CheckedContinuation<WebSourceHTTPDecoder.Response, Error>?
  func wait() async throws -> WebSourceHTTPDecoder.Response {
    try await withCheckedThrowingContinuation { continuation = $0 }
  }
  func entered() async {
    for _ in 0..<10_000 { if continuation != nil { return }; await Task.yield() }
    preconditionFailure("Web fetch did not reach the suspended boundary")
  }
  func resume(_ value: WebSourceHTTPDecoder.Response) { continuation!.resume(returning: value); continuation = nil }
}
