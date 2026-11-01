import Foundation
import SQLite3

@main
struct ProjectSourcePreparationChecks {
  enum Failure: Error { case offline }
  static let metadata = ProjectYouTubeMetadata.Value(title: "架空の動画タイトル", author: "架空の著者")
  static let thumbnail = Data([0xff, 0xd8, 0xff, 0xd9])
  static var extracted: ProjectSourceExtractionResult {
    ProjectSourceExtractionResult(blocks: [ProjectSourceText(text: "抽出fixtureの本文")],
      thumbnail: thumbnail, notice: "一部だけのfixture", coverage: .partial)
  }

  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    try await happyPaths(root)
    for stage in 0..<5 {
      for change in 0..<12 { try await race(root, stage: stage, change: change) }
    }
    for youtube in [false, true] {
      try await cancellation(root, youtube: youtube)
      try await rollback(root, youtube: youtube)
      try await rejectedStart(root, youtube: youtube)
    }
    try await rejectedMetadata(root)
    try await oversized(root)
    print("ProjectSourcePreparationChecks: passed (production metadata/local orchestration, 60 suspended-result/file-write races, cancellation, duplicate execution, SQLite failure/retry/reopen, file cleanup and reader size bounds; extraction/network/downsample payloads and model state are fixtures, no network)")
  }

  @MainActor static func fixture(_ root: URL, _ label: String, youtube: Bool) async throws -> (MemoraModel, UUID) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("\(label).sqlite"))
    let project = MemoraSpace(id: UUID(), name: "架空のプロジェクト", symbol: "folder")
    model.spaces = [project]
    var source = ProjectSource(projectID: project.id, kind: youtube ? .youtube : .document, title: "保存した名前")
    if youtube {
      source.originalURL = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
      source.metadata = ["retained": "既存情報"]
    } else {
      source.localFileReference = try await ProjectSourceFiles.shared.write(Data("元のファイル".utf8), extension: "txt")
    }
    precondition(model.storeProjectSource(source))
    return (model, source.id)
  }

  @MainActor static func happyPaths(_ root: URL) async throws {
    let (model, id) = try await fixture(root, "youtube", youtube: true)
    await model.prepareProjectYouTube(id, fetchMetadata: { _ in metadata }, fetchThumbnail: { _ in throw Failure.offline })
    let partial = model.source(id: id)!
    precondition(partial.title == metadata.title && partial.metadata?["youtubeAuthor"] == metadata.author)
    precondition(partial.metadata?["retained"] == "既存情報" && partial.metadata?["thumbnailError"] != nil)
    precondition(partial.processingStatus == .unavailable && !partial.canProvideText && !partial.privacy.allowsCloudAI)
    await model.prepareProjectYouTube(id, fetchMetadata: { _ in preconditionFailure("Metadata was fetched twice") },
      fetchThumbnail: { _ in thumbnail })
    let complete = model.source(id: id)!
    precondition(complete.metadata?["thumbnailError"] == nil && complete.thumbnailReference != nil && !complete.canProvideText)
    let bytes = try Data(contentsOf: ProjectSourceFiles.resolve(complete.thumbnailReference!)!)
    precondition(bytes == thumbnail)
    try verifyDurable(model)

    let (local, localID) = try await fixture(root, "local", youtube: false)
    let gate = PreparationGate<ProjectSourceExtractionResult>()
    let job = Task { await local.prepareProjectLocalSource(localID, extract: { _ in try await gate.wait() }) }
    await gate.entered()
    await local.prepareProjectLocalSource(localID, extract: { _ in preconditionFailure("Concurrent extraction started") })
    gate.resume(extracted)
    await job.value
    let saved = local.source(id: localID)!
    precondition(saved.processingStatus == .ready && saved.textCoverage == .partial && saved.errorInformation == extracted.notice)
    precondition(saved.localFileReference != nil && saved.thumbnailReference != nil)
    let text = try ProjectSourceTextReader.read(saved.extractedTextReference!).first?.text
    precondition(text == extracted.blocks[0].text && local.projectSourceProcessingIDs.isEmpty)
    try verifyDurable(local)

    let (offline, offlineID) = try await fixture(root, "offline", youtube: true)
    await offline.prepareProjectYouTube(offlineID, fetchMetadata: { _ in throw Failure.offline },
      fetchThumbnail: { _ in preconditionFailure("Thumbnail fetched after failed metadata") })
    precondition(offline.source(id: offlineID)!.metadata?["youtubeTitle"] == nil)
    precondition(offline.source(id: offlineID)!.processingStatus == .unavailable && offline.projectSourceProcessingIDs.isEmpty)
    try verifyDurable(offline)

    let before = try files()
    offline.currentTeamID = "unconfigured"
    await offline.prepareProjectYouTube(offlineID, fetchMetadata: { _ in preconditionFailure("Team fetched metadata") },
      fetchThumbnail: { _ in preconditionFailure("Team fetched thumbnail") })
    local.currentTeamID = "unconfigured"
    await local.prepareProjectLocalSource(localID, extract: { _ in preconditionFailure("Team extracted personal source") })
    expect(try files() == before)
  }

  // stages: metadata response, thumbnail response, extraction response, thumbnail
  // file write, and extracted-text file write. All writes are the real file actor.
  @MainActor static func race(_ root: URL, stage: Int, change: Int) async throws {
    let youtube = stage == 0 || stage == 1 || stage == 3
    let (model, id) = try await fixture(root, "race-\(stage)-\(change)", youtube: youtube)
    let before = try files()
    let gate = PreparationGate<Void>()
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    var hold: Task<Bool, Never>?
    var writing = false
    func holdFiles() {
      hold = Task.detached { await ProjectSourceFiles.shared.holdForPreparationCheck(entered: entered, release: release) }
      precondition(entered.wait(timeout: .now() + 10) == .success)
      writing = true
    }
    defer { release.signal() }
    let operation = Task { @MainActor in
      if youtube {
        await model.prepareProjectYouTube(id, fetchMetadata: { _ in
          if stage == 0 { try await gate.wait() }
          return metadata
        }, fetchThumbnail: { _ in
          if stage == 1 { try await gate.wait() }
          if stage == 3 { holdFiles() }
          return thumbnail
        })
      } else {
        await model.prepareProjectLocalSource(id, extract: { _ in
          if stage == 2 { try await gate.wait() }
          if stage == 4 { holdFiles() }
          return extracted
        })
      }
    }
    if stage < 3 { await gate.entered() }
    else {
      for _ in 0..<10_000 { if writing { break }; await Task.yield() }
      precondition(writing)
    }
    switch change {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "更新されたプロジェクト"
    case 6: model.projectSources[0].privacy.protect(.personal)
    case 7: model.projectSources[0].projectID = nil
    case 8: model.projectSources[0].title = "先に編集された名前"
    case 9: model.projectSources = []
    case 10: model.projectSources[0].kind = .note
    default: model.aiWorkspaceGeneration = UUID()
    }
    let snapshot = model.projectSources
    if (6...10).contains(change) {
      precondition(model.persistNow(snapshot, forKey: MemoraModel.StorageKey.projectSources))
    }
    let durable = try reload(model)
    if stage < 3 { gate.resume(()) } else { release.signal() }
    await operation.value
    if let hold { expect(await hold.value) }
    var expected = snapshot
    if model.currentTeamID == nil && !model.isRestoring && !model.isStoreProtected {
      for index in expected.indices where expected[index].processingStatus == .processing {
        expected[index].processingStatus = expected[index].kind == .youtube ? .unavailable : .failed
        expected[index].errorInformation = "処理は中断されました。ソースは保持しています。必要に応じて再試行してください。自動では再開しません。"
      }
    }
    precondition(model.projectSources == expected && model.projectSourceProcessingIDs.isEmpty)
    expect(try reload(model) == (expected == snapshot ? durable : expected) && files() == before)
  }

  @MainActor static func cancellation(_ root: URL, youtube: Bool) async throws {
    let (model, id) = try await fixture(root, "cancel-\(youtube)", youtube: youtube)
    let gate = PreparationGate<Void>()
    let operation = Task { @MainActor in
      if youtube {
        await model.prepareProjectYouTube(id, fetchMetadata: { _ in try await gate.wait(); return metadata },
          fetchThumbnail: { _ in preconditionFailure("Cancelled operation fetched thumbnail") })
      } else {
        await model.prepareProjectLocalSource(id, extract: { _ in try await gate.wait(); return extracted })
      }
    }
    await gate.entered()
    operation.cancel()
    gate.resume(())
    await operation.value
    let source = model.source(id: id)!
    precondition(!source.canProvideText && source.thumbnailReference == nil && source.extractedTextReference == nil)
    precondition(source.processingStatus == (youtube ? .unavailable : .failed) && model.projectSourceProcessingIDs.isEmpty)
    precondition(source.errorInformation?.contains("停止") == true)
    try verifyDurable(model)
  }

  @MainActor static func rollback(_ root: URL, youtube: Bool) async throws {
    let (model, id) = try await fixture(root, "rollback-\(youtube)", youtube: youtube)
    let before = try files()
    func rejectWrites() throws {
      try sql("CREATE TRIGGER fail_prepare BEFORE INSERT ON documents WHEN NEW.key = 'memoraProjectSources' BEGIN SELECT RAISE(ABORT, 'prepare check'); END;", model.storeURL)
    }
    if youtube {
      await model.prepareProjectYouTube(id, fetchMetadata: { _ in metadata }, fetchThumbnail: { _ in
        try rejectWrites(); return thumbnail
      })
    } else {
      await model.prepareProjectLocalSource(id, extract: { _ in try rejectWrites(); return extracted })
    }
    precondition(model.source(id: id)!.thumbnailReference == nil && model.source(id: id)!.extractedTextReference == nil)
    precondition(model.persistenceFailureMessage != nil && model.projectSourceProcessingIDs.isEmpty)
    expect(try files() == before)
    try verifyDurable(model)
    try sql("DROP TRIGGER fail_prepare;", model.storeURL)
    if youtube {
      await model.prepareProjectYouTube(id, fetchMetadata: { _ in metadata }, fetchThumbnail: { _ in thumbnail })
    } else { await model.prepareProjectLocalSource(id, extract: { _ in extracted }) }
    precondition(model.source(id: id)!.thumbnailReference != nil)
    try verifyDurable(model)
  }

  @MainActor static func oversized(_ root: URL) async throws {
    let (model, id) = try await fixture(root, "oversized", youtube: false)
    let before = try files()
    await model.prepareProjectLocalSource(id, extract: { _ in
      ProjectSourceExtractionResult(blocks: [ProjectSourceText(text: String(repeating: "\u{1}", count: ProjectSourceTextReader.maximumBytes / 6 + 1))])
    })
    precondition(model.source(id: id)!.processingStatus == .failed && !model.source(id: id)!.canProvideText)
    precondition(model.source(id: id)!.errorInformation?.contains("16MB") == true)
    expect(try files() == before)
    try verifyDurable(model)
  }

  @MainActor static func rejectedStart(_ root: URL, youtube: Bool) async throws {
    let (model, id) = try await fixture(root, "start-failure-\(youtube)", youtube: youtube)
    let original = model.projectSources
    let before = try files()
    try sql("CREATE TRIGGER reject_start BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'start check'); END;", model.storeURL)
    if youtube {
      await model.prepareProjectYouTube(id, fetchMetadata: { _ in preconditionFailure("Metadata fetched despite failed initial save") },
        fetchThumbnail: { _ in preconditionFailure("Thumbnail fetched despite failed initial save") })
    } else {
      await model.prepareProjectLocalSource(id, extract: { _ in preconditionFailure("Extracted despite failed initial save") })
    }
    precondition(model.projectSources == original && model.projectSourceProcessingIDs.isEmpty)
    expect(try files() == before)
    try verifyDurable(model)
    try sql("DROP TRIGGER reject_start;", model.storeURL)
  }

  @MainActor static func rejectedMetadata(_ root: URL) async throws {
    let (model, id) = try await fixture(root, "metadata-save-failure", youtube: true)
    let before = try files()
    await model.prepareProjectYouTube(id, fetchMetadata: { _ in
      try sql("CREATE TRIGGER reject_metadata BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'metadata check'); END;", model.storeURL)
      return metadata
    }, fetchThumbnail: { _ in preconditionFailure("Thumbnail fetched despite failed metadata save") })
    precondition(model.source(id: id)!.metadata?["youtubeTitle"] == nil && model.projectSourceProcessingIDs.isEmpty)
    expect(try files() == before)
    try verifyDurable(model)
    try sql("DROP TRIGGER reject_metadata;", model.storeURL)
    await model.prepareProjectYouTube(id, fetchMetadata: { _ in metadata }, fetchThumbnail: { _ in thumbnail })
    precondition(model.source(id: id)!.thumbnailReference != nil)
    try verifyDurable(model)
  }

  @MainActor static func verifyDurable(_ model: MemoraModel) throws {
    expect(try reload(model) == model.projectSources)
  }
  static func expect(_ value: Bool) { precondition(value) }
  @MainActor static func reload(_ model: MemoraModel) throws -> [ProjectSource] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let bytes) = store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Missing source document") }
    return try JSONDecoder().decode([ProjectSource].self, from: bytes)
  }
  static func files() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
  }
  static func sql(_ statement: String, _ url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }
}

@MainActor
private final class PreparationGate<Value> {
  var continuation: CheckedContinuation<Value, Error>?
  func wait() async throws -> Value {
    try await withCheckedThrowingContinuation { continuation = $0 }
  }
  func entered() async {
    for _ in 0..<10_000 { if continuation != nil { return }; await Task.yield() }
    preconditionFailure("Preparation did not reach its suspended boundary")
  }
  func resume(_ value: Value) { continuation!.resume(returning: value); continuation = nil }
}

extension ProjectSourceFiles {
  func holdForPreparationCheck(entered: DispatchSemaphore, release: DispatchSemaphore) -> Bool {
    entered.signal()
    return release.wait(timeout: .now() + 10) == .success
  }
}
