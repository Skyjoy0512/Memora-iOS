import Foundation
import SQLite3

@main
struct ProjectSourceImportChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try await normalPaths(root)
    for stage in 0..<4 {
      for change in 0..<8 { try await race(root, stage: stage, change: change) }
    }
    try await conversationCopy(root)
    try await rollback(root)
    try await mutations(root)
    try contextPolicy(root)
    print("ProjectSourceImportChecks: passed (production file copy/transfer registration, fingerprints, SQLite reopen, 32 context races before load/during copy/after transfer/after registration, dedup and committed-file retention, SQL rollback/retry, detach/delete workspace guards; OS preparation/audio and model state are fixtures, no network)")
  }

  @MainActor static func fixture(_ root: URL, _ name: String) throws -> (MemoraModel, UUID) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("\(name).sqlite"))
    let project = MemoraSpace(id: UUID(), name: "架空の取込先", symbol: "folder")
    model.spaces = [project]
    return (model, project.id)
  }
  static func original(_ root: URL, _ name: String) throws -> URL {
    let url = root.appendingPathComponent("\(name).txt")
    try Data("保持する元のファイル".utf8).write(to: url, options: .atomic)
    return url
  }

  @MainActor static func normalPaths(_ root: URL) async throws {
    let (model, projectID) = try fixture(root, "normal")
    let url = try original(root, "original")
    let context = LocalImportContext(projectID: projectID, in: model)!
    guard let id = try await model.importProjectFile(url, projectID: projectID), let source = model.source(id: id) else {
      preconditionFailure("File was not registered")
    }
    precondition(source.kind == .document && source.projectID == projectID && !source.privacy.allowsCloudAI)
    precondition(source.contentFingerprint?.count == 64 && model.preparedSourceIDs == [id])
    expect(try Data(contentsOf: ProjectSourceFiles.resolve(source.localFileReference!)!) == Data(contentsOf: url))
    expect(try reload(model) == [source])
    let before = try files()
    expect(try await model.importProjectFile(url, projectID: projectID) == id)
    expect(try files() == before && reload(model) == [source])
    let reused = ProjectSourceFiles.Receipt(reference: source.localFileReference!, fingerprint: source.contentFingerprint!)
    expect(await model.addProjectFile(receipt: reused, title: "既存参照", context: context) == id)
    expect(try files() == before)
    let other = MemoraSpace(id: UUID(), name: "別の保存先", symbol: "folder")
    model.spaces.append(other)
    expect(try await model.importProjectFile(url, projectID: other.id, importContext: context) == nil)
    let audio = root.appendingPathComponent("route.wav")
    try Data([0]).write(to: audio)
    let audioID = try await model.importProjectFile(audio, projectID: projectID)
    precondition(audioID != nil && model.source(id: audioID!)?.kind == .audio)
    precondition(model.audioImportCalls == 0 && model.projectSources.count == 2)
    expect(try await model.importProjectFile(audio, projectID: projectID) == audioID)
    model.currentTeamID = "unconfigured"
    expect(try await model.importProjectFile(audio, projectID: projectID) == nil)
    precondition(model.audioImportCalls == 0)
    expect(try await model.importProjectFile(url, projectID: nil) == nil)
    model.currentTeamID = nil
    let libraryID = try await model.importProjectFile(url, projectID: nil)
    precondition(libraryID != nil && model.source(id: libraryID!)?.projectID == nil)
    expect(try Data(contentsOf: url) == Data("保持する元のファイル".utf8))
  }

  @MainActor static func conversationCopy(_ root: URL) async throws {
    let (model, projectID) = try fixture(root, "conversation-copy")
    let url = try original(root, "conversation-original")
    let originalURL = URL(string: "https://example.org/paper.pdf")!
    let gate = ImportGate()
    model.preparationHook = { _ in await gate.wait() }
    guard let id = try await model.importProjectFile(url, projectID: projectID,
      waitsForPreparation: false, sourceTitle: "論文のタイトル", originalURL: originalURL) else {
      preconditionFailure("Saving waited for preparation or failed")
    }
    let saved = model.source(id: id)!
    precondition(saved.title == "論文のタイトル" && saved.originalURL == originalURL && !saved.privacy.allowsCloudAI)
    expect(try reload(model) == [saved])
    await gate.entered()
    let before = try files()
    try Data("URLが同じ別バージョン".utf8).write(to: url)
    expect(try await model.importProjectFile(url, projectID: projectID, waitsForPreparation: false,
      sourceTitle: "上書きしない", originalURL: originalURL) == id)
    precondition(model.source(id: id) == saved)
    expect(try files() == before)
    gate.resume()
    if let job = model.sourcePreparationJobs[id]?.task { await job.value }
    model.preparationHook = nil
    let libraryID = try await model.importProjectFile(url, projectID: nil,
      sourceTitle: "個人の資料", originalURL: originalURL)
    precondition(libraryID != nil && libraryID != id && model.source(id: libraryID!)?.projectID == nil)
    print("PASS conversation copy saves title/URL/privacy atomically before deferred preparation, deduplicates URL without overwriting evidence, preserves project scope")
  }

  @MainActor static func race(_ root: URL, stage: Int, change: Int) async throws {
    let (model, projectID) = try fixture(root, "race-\(stage)-\(change)")
    let url = try original(root, "race-input-\(stage)-\(change)")
    let context = LocalImportContext(projectID: projectID, in: model)!
    let before = try files()
    let gate = ImportGate()
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    var hold: Task<Bool, Never>?
    if stage == 1 {
      hold = Task.detached { await ProjectSourceFiles.shared.holdForImportCheck(entered: entered, release: release) }
      precondition(entered.wait(timeout: .now() + 10) == .success)
    }
    defer { release.signal() }
    if stage == 3 { model.preparationHook = { _ in await gate.wait() } }
    var started = false
    var registered: ProjectSource?
    let operation = Task { @MainActor in
      started = true
      if stage == 0 { await gate.wait() }
      if stage == 1 || stage == 3 {
        return try await model.importProjectFile(url, projectID: projectID, importContext: context)
      }
      return try await model.importProjectSource(title: "転送済み写真fixture", context: context) {
        let receipt = try await ProjectSourceFiles.shared.copy(url)
        await gate.wait()
        return receipt
      }
    }
    if stage == 1 {
      for _ in 0..<10_000 { if started { break }; await Task.yield() }
      precondition(started)
    } else { await gate.entered() }
    if stage == 3 { registered = model.projectSources.first; precondition(registered != nil) }
    switch change {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "更新されたproject"
    case 6: operation.cancel()
    default: model.aiWorkspaceGeneration = UUID()
    }
    if stage == 1 { release.signal() } else { gate.resume() }
    do { expect(try await operation.value == nil) }
    catch is CancellationError { precondition(change == 6) }
    if let hold { expect(await hold.value) }
    if let registered {
      precondition(model.projectSources == [registered])
      expect(try reload(model) == [registered])
      expect(try Data(contentsOf: ProjectSourceFiles.resolve(registered.localFileReference!)!) == Data(contentsOf: url))
    } else {
      precondition(model.projectSources.isEmpty && model.preparedSourceIDs.isEmpty)
      expect(try files() == before)
    }
    expect(try Data(contentsOf: url) == Data("保持する元のファイル".utf8))
  }

  @MainActor static func rollback(_ root: URL) async throws {
    let (model, projectID) = try fixture(root, "rollback")
    let url = try original(root, "rollback-input")
    let before = try files()
    try sql("CREATE TRIGGER reject_import BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'import check'); END;", model.storeURL)
    for local in [false, true] {
      model.persistenceFailureMessage = nil
      expect(try await model.importProjectFile(url, projectID: projectID, presentsErrorsLocally: local) == nil)
      precondition(model.projectSources.isEmpty && model.preparedSourceIDs.isEmpty)
      precondition((model.persistenceFailureMessage == nil) == local)
      expect(try files() == before)
      guard case .missing = model.store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Failed import persisted") }
    }
    // Global error presentation must be restored immediately after the local
    // synchronous registration, not suppressed across unrelated async work.
    precondition(!model.persistNow([ProjectSource](), forKey: MemoraModel.StorageKey.projectSources))
    precondition(model.persistenceFailureMessage != nil)
    try sql("DROP TRIGGER reject_import;", model.storeURL)
    expect(try await model.importProjectFile(url, projectID: projectID) != nil)
    expect(try reload(model) == model.projectSources)
  }

  @MainActor static func mutations(_ root: URL) async throws {
    let (model, projectID) = try fixture(root, "mutations")
    let id = try await model.importProjectFile(original(root, "mutation-input"), projectID: projectID)!
    let source = model.source(id: id)!
    let before = try files()
    for state in 0..<3 {
      if state == 0 { model.currentTeamID = "unconfigured" }
      if state == 1 { model.isRestoring = true }
      if state == 2 { model.isStoreProtected = true }
      precondition(!model.detachProjectSource(id) && !model.deleteProjectSource(id))
      precondition(model.projectSources == [source])
      expect(try reload(model) == [source] && files() == before)
      model.currentTeamID = nil; model.isRestoring = false; model.isStoreProtected = false
    }
    try sql("CREATE TRIGGER reject_delete BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'delete check'); END;", model.storeURL)
    precondition(!model.deleteProjectSource(id))
    precondition(model.discardedSourceExtractions.isEmpty)
    expect(try reload(model) == [source] && files() == before)
    try sql("DROP TRIGGER reject_delete;", model.storeURL)
    precondition(model.detachProjectSource(id) && model.source(id: id)!.projectID == nil)
    let detached = model.source(id: id)!
    var shared = detached
    shared.id = UUID()
    precondition(model.storeProjectSource(shared) && model.deleteProjectSource(id))
    precondition(model.discardedSourceExtractions == [detached])
    await Task.yield()
    expect(try reload(model) == [shared])
    expect(try Data(contentsOf: ProjectSourceFiles.resolve(shared.localFileReference!)!) == Data("保持する元のファイル".utf8))
    model.retainedOfficeFileReferences = Set(shared.fileReferences)
    precondition(model.deleteProjectSource(shared.id))
    try await Task.sleep(for: .milliseconds(25))
    expect(try reload(model).isEmpty)
    expect(try Data(contentsOf: ProjectSourceFiles.resolve(shared.localFileReference!)!) == Data("保持する元のファイル".utf8))
    print("PASS source deletion preserves files retained by Office documents/history/templates (reference registry fixture)")

    let lateID = try await model.importProjectFile(original(root, "late-delete-input"), projectID: projectID)!
    let late = model.source(id: lateID)!
    precondition(model.deleteProjectSource(lateID))
    model.currentTeamID = "other"; model.currentTeamID = nil
    try await Task.sleep(for: .milliseconds(25))
    expect(try Data(contentsOf: ProjectSourceFiles.resolve(late.localFileReference!)!) == Data("保持する元のファイル".utf8))
    print("PASS source deletion cleanup refuses a changed workspace generation")
  }

  @MainActor static func contextPolicy(_ root: URL) throws {
    let (model, id) = try fixture(root, "context")
    let filed = LocalImportContext(projectID: id, in: model)!
    let global = LocalImportContext(in: model)!
    model.spaces = []
    precondition(!filed.isCurrent(in: model) && filed.isCurrent(in: model, allowsRemovedProject: true))
    precondition(global.isCurrent(in: model))
    model.currentTeamID = "other"; model.currentTeamID = nil
    precondition(!filed.isCurrent(in: model, allowsRemovedProject: true) && !global.isCurrent(in: model))
    model.currentTeamID = "unconfigured"
    precondition(LocalImportContext(in: model) == nil)
  }

  static func expect(_ value: Bool) { precondition(value) }
  @MainActor static func reload(_ model: MemoraModel) throws -> [ProjectSource] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Missing sources") }
    return try JSONDecoder().decode([ProjectSource].self, from: data)
  }
  static func files() throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: ProjectSourceFiles.directory.path) else { return [] }
    return Set(try FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
  }
  static func sql(_ statement: String, _ url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }
}

@MainActor private final class ImportGate {
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async { await withCheckedContinuation { continuation = $0 } }
  func entered() async {
    for _ in 0..<10_000 { if continuation != nil { return }; await Task.yield() }
    preconditionFailure("Import did not reach its suspended boundary")
  }
  func resume() { continuation!.resume(); continuation = nil }
}

extension ProjectSourceFiles {
  func holdForImportCheck(entered: DispatchSemaphore, release: DispatchSemaphore) -> Bool {
    entered.signal()
    return release.wait(timeout: .now() + 10) == .success
  }
}
