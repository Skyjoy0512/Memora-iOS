import Foundation
import SQLite3
import Darwin

@main
struct BackupRestoreChecks {
  enum FixtureFailure: Error { case rejected }

  @MainActor static func main() async throws {
    let fm = FileManager.default
    try fm.createDirectory(at: FixtureFiles.root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: FixtureFiles.root) }
    let input = FixtureFiles.root.appendingPathComponent("input")
    try fm.createDirectory(at: input, withIntermediateDirectories: true)
    try fm.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    try fm.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    try fm.createDirectory(at: MediaFiles.photosDirectory, withIntermediateDirectories: true)

    let docx = try Data(contentsOf: URL(fileURLWithPath: "docs/fixtures/ask-ai-artifacts/generated.docx"))
    let pptx = try Data(contentsOf: URL(fileURLWithPath: "docs/fixtures/ask-ai-artifacts/generated.pptx"))
    let audio = Data("fixture audio, never played".utf8)
    let photo = Data("fixture image, never displayed".utf8)
    let workspaceFiles = ["template.docx": docx, "artifact.pptx": pptx, "source.txt": Data("根拠の本文".utf8)]
    for (name, data) in workspaceFiles { try data.write(to: ProjectSourceFiles.resolve(name)!) }
    try audio.write(to: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    try photo.write(to: MediaFiles.photosDirectory.appendingPathComponent("photo.jpg"))
    let meeting = Meeting(rawAudioReference: "audio.m4a", photoFileNames: ["photo.jpg"])
    let project = MemoraSpace()
    let person = Person()
    let now = Date.now
    var memory = AIMemory(id: UUID(), text: "簡潔な文章を好む", origin: .told, createdAt: now,
      semantic: .init(type: .style, value: "簡潔な文章を好む", sourceReference: "settings", observedAt: now, updatedAt: now, validFrom: now))
    memory = memory.edited(text: "結論から簡潔に書く", status: .current, kind: .style, sensitivity: .standard, predicate: "文章", workspaceID: nil)
    var draft = MailDraft(recipients: [], subject: "会議のフォローアップ", body: "決定事項を共有します。", cc: ["fixture@example.com"])
    draft.personIDs = [person.id]; draft.projectID = project.id; draft.recordIDs = [meeting.id]
    let template = CompanyTemplate(name: "会社書式", format: .docx, fileReference: "template.docx", projectID: project.id,
      analysis: try CompanyTemplateEngine.analyze(docx, format: .docx))
    var document = MemoraDocument(title: "提案資料", kind: .slides, slides: [DocumentSlide(title: "概要", bullets: ["架空の内容"])], spaceID: project.id)
    document.artifactFileReference = "artifact.pptx"; document.artifactFormat = "PPTX"
    document.sourceRecordIDs = [meeting.id]
    let source = ProjectSource(projectID: project.id, kind: .note, title: "根拠", extractedTextReference: "source.txt")
    let sessionID = UUID()
    let episode = AIEpisode(id: UUID(), sessionID: sessionID, date: now, topic: "提案書", objective: "資料作成", summary: "会社書式を確認した", personIDs: [person.id], projectIDs: [project.id], recordIDs: [meeting.id], documentIDs: [document.id])
    let history = AIConversationEntry(id: UUID(), question: "前回の提案書", answer: "保存しました", scopeLabel: "すべて", createdAt: now, episode: episode)
    let package = try BackupPackage.write(meetings: [meeting], spaces: [project], tasks: [], lifeLogEntries: [], people: [person], aiHistory: [history], aiMemories: [memory], mailDrafts: [draft], companyTemplates: [template], documents: [document], projectSources: [source], into: input)
    let manifest = try BackupPackage.read(from: package)
    precondition(manifest.aiMemories == [memory] && manifest.mailDrafts == [draft] && manifest.companyTemplates == [template])
    precondition(manifest.documents == [document] && manifest.aiHistory.first?.episode == episode)
    for (name, bytes) in workspaceFiles {
      let restored = try Data(contentsOf: package.appendingPathComponent("workspace/" + name))
      precondition(restored == bytes)
    }
    let manifestURL = package.appendingPathComponent(BackupPackage.manifestName)
    let originalJSON = try Data(contentsOf: manifestURL)
    var json = try JSONSerialization.jsonObject(with: originalJSON) as! [String: Any]
    for key in ["aiMemories", "mailDrafts", "companyTemplates", "documents", "projectSources", "projectChats", "customSkills", "skillSelections", "webResearchReports"] { json.removeValue(forKey: key) }
    json["version"] = 1
    var oldHistory = json["aiHistory"] as! [[String: Any]]
    for index in oldHistory.indices { oldHistory[index].removeValue(forKey: "episode") }
    json["aiHistory"] = oldHistory
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)
    let legacy = try BackupPackage.read(from: package)
    precondition(legacy.aiMemories == nil && legacy.mailDrafts == nil && legacy.companyTemplates == nil && legacy.documents == nil && legacy.aiHistory.first?.episode == nil)
    try originalJSON.write(to: manifestURL, options: .atomic)

    var invalid = manifest
    invalid.documents = [document, document]
    try reject(invalid, in: package)
    invalid = manifest; invalid.mailDrafts?[0].recipients = Array(repeating: "fixture@example.com", count: 101)
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactFileReference = "../escape.pptx"
    try reject(invalid, in: package)
    try originalJSON.write(to: manifestURL, options: .atomic)

    // A valid leaf beneath a linked directory must not be accepted as package data.
    let folder = package.appendingPathComponent("workspace")
    let moved = package.appendingPathComponent("held-workspace")
    try fm.moveItem(at: folder, to: moved)
    try fm.createSymbolicLink(at: folder, withDestinationURL: moved)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: folder); try fm.moveItem(at: moved, to: folder)
    let heldManifest = package.appendingPathComponent("held-manifest")
    try fm.moveItem(at: manifestURL, to: heldManifest)
    try fm.createSymbolicLink(at: manifestURL, withDestinationURL: heldManifest)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: manifestURL); try fm.moveItem(at: heldManifest, to: manifestURL)

    try Data("{broken".utf8).write(to: manifestURL, options: .atomic)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try originalJSON.write(to: manifestURL, options: .atomic)
    let artifactURL = folder.appendingPathComponent("artifact.pptx")
    try fm.removeItem(at: artifactURL)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try pptx.write(to: artifactURL)
    let largeURL = folder.appendingPathComponent("oversize.docx")
    fm.createFile(atPath: largeURL.path, contents: nil)
    let largeHandle = try FileHandle(forWritingTo: largeURL)
    try largeHandle.truncate(atOffset: UInt64(ProjectSourceFiles.maximumFileBytes + 1)); try largeHandle.close()
    invalid = manifest; invalid.documents?[0].artifactFileReference = "oversize.docx"
    try reject(invalid, in: package)
    try fm.removeItem(at: largeURL)
    let mediaFolder = package.appendingPathComponent("media")
    let heldMedia = package.appendingPathComponent("held-media")
    try fm.moveItem(at: mediaFolder, to: heldMedia)
    try fm.createSymbolicLink(at: mediaFolder, withDestinationURL: heldMedia)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: mediaFolder); try fm.moveItem(at: heldMedia, to: mediaFolder)

    // Clear only this isolated destination, simulating a fresh app container.
    for name in workspaceFiles.keys { try fm.removeItem(at: ProjectSourceFiles.resolve(name)!) }
    try fm.removeItem(at: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    try fm.removeItem(at: MediaFiles.photosDirectory.appendingPathComponent("photo.jpg"))
    // Actually restore the pre-feature package, rather than only decoding its JSON.
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)
    var legacyCommitted = false
    try await BackupRestoreTransaction.restore(from: package) { value in
      precondition(value.aiMemories == nil && value.companyTemplates == nil && value.mailDrafts == nil)
      legacyCommitted = true
    }
    precondition(legacyCommitted)
    let legacyAudio = try Data(contentsOf: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    precondition(legacyAudio == audio)
    BackupPackage.removeInstalledMedia([("audio.m4a", true), ("photo.jpg", false)])
    try originalJSON.write(to: manifestURL, options: .atomic)
    precondition(emptyDestinations())

    let storeURL = FixtureFiles.root.appendingPathComponent("records.sqlite")
    let store = LocalStore(fileURL: storeURL)
    try store.prepare()
    try store.write("unrelated", data: Data("keep".utf8))
    var db: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_fixture BEFORE INSERT ON documents WHEN NEW.key = 'mail' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    do {
      try await BackupRestoreTransaction.restore(from: package) { value in
        try store.applyBatch(writes: try writes(value), removing: [])
      }
      preconditionFailure("SQLite failure was reported as success")
    } catch {}
    precondition(emptyDestinations())
    if case .missing = store.readOutcome("memories") {} else { preconditionFailure("Partial records committed") }
    if case .data(let bytes) = store.readOutcome("unrelated") { precondition(bytes == Data("keep".utf8)) } else { preconditionFailure() }
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_fixture;", nil, nil, nil) == SQLITE_OK)

    do {
      try await BackupRestoreTransaction.restore(from: package) { _ in throw FixtureFailure.rejected }
      preconditionFailure("Changed workspace/record gate accepted")
    } catch FixtureFailure.rejected {}
    precondition(emptyDestinations())
    let cancelled = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Cancelled restore committed") }
    }
    do { try await cancelled.value; preconditionFailure("Cancellation ignored") } catch is CancellationError {}
    precondition(emptyDestinations())

    // Hold the main actor until preparation has installed files. A cancelled parent
    // must roll them back before its commit callback can run.
    var preparationStarted = false
    let stagedCancellation = Task { @MainActor in
      preparationStarted = true
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Cancelled prepared restore committed") }
    }
    while !preparationStarted { await Task.yield() }
    let deadline = Date().addingTimeInterval(5)
    while !fm.fileExists(atPath: ProjectSourceFiles.resolve("template.docx")!.path) && Date() < deadline { usleep(1_000) }
    precondition(fm.fileExists(atPath: ProjectSourceFiles.resolve("template.docx")!.path), "Preparation never reached its suspended commit")
    stagedCancellation.cancel()
    do { try await stagedCancellation.value; preconditionFailure("Prepared cancellation ignored") } catch is CancellationError {}
    precondition(emptyDestinations())

    // Sorted installation encounters a later conflict; earlier copies must be taken back.
    let conflict = ProjectSourceFiles.resolve("template.docx")!
    try Data("existing bytes".utf8).write(to: conflict)
    do {
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Conflict committed") }
      preconditionFailure("Conflict ignored")
    } catch BackupPackage.BackupError.mediaConflict {}
    let existing = try Data(contentsOf: conflict)
    precondition(existing == Data("existing bytes".utf8))
    precondition(!fm.fileExists(atPath: ProjectSourceFiles.resolve("artifact.pptx")!.path))
    precondition(!fm.fileExists(atPath: MediaFiles.directory.appendingPathComponent("audio.m4a").path))
    try fm.removeItem(at: conflict)

    try await BackupRestoreTransaction.restore(from: package) { value in
      try store.applyBatch(writes: try writes(value), removing: [])
    }
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    let memories = try JSONDecoder().decode([AIMemory].self, from: read(reopened, "memories"))
    let drafts = try JSONDecoder().decode([MailDraft].self, from: read(reopened, "mail"))
    let templates = try JSONDecoder().decode([CompanyTemplate].self, from: read(reopened, "templates"))
    let documents = try JSONDecoder().decode([MemoraDocument].self, from: read(reopened, "documents"))
    precondition(memories == [memory] && drafts == [draft] && templates == [template] && documents == [document])
    for (name, bytes) in workspaceFiles {
      let restored = try Data(contentsOf: ProjectSourceFiles.resolve(name)!)
      precondition(restored == bytes)
    }
    let restoredAudio = try Data(contentsOf: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    precondition(restoredAudio == audio)
    print("BackupRestoreChecks: passed (production package/restore + real SQLite, new metadata/files roundtrip, legacy restore, duplicate documents, recipient limits, truncated/missing/oversize, traversal/symlinks, DB rollback, cancellation/gate, conflict preserves bytes, reopen; isolated fixtures only)")
  }

  static func writes(_ value: BackupPackage.Manifest) throws -> [(key: String, data: Data)] {
    [("memories", try JSONEncoder().encode(value.aiMemories)), ("mail", try JSONEncoder().encode(value.mailDrafts)),
     ("templates", try JSONEncoder().encode(value.companyTemplates)), ("documents", try JSONEncoder().encode(value.documents))]
  }
  static func read(_ store: LocalStore, _ key: String) -> Data {
    guard case .data(let data) = store.readOutcome(key) else { preconditionFailure("Missing restored key") }; return data
  }
  static func reject(_ manifest: BackupPackage.Manifest, in package: URL) throws {
    let url = package.appendingPathComponent(BackupPackage.manifestName)
    let original = try Data(contentsOf: url)
    defer { try? original.write(to: url, options: .atomic) }
    try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
    try expectFailure { _ = try BackupPackage.read(from: package) }
  }
  static func expectFailure(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    preconditionFailure("Invalid backup accepted")
  }
  static func emptyDestinations() -> Bool {
    [ProjectSourceFiles.directory, MediaFiles.directory, MediaFiles.photosDirectory].allSatisfy {
      ((try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []).isEmpty
    }
  }
}

// Only legacy record shapes and container locations are fixtures. Package validation,
// new record codecs, file installation, cancellation and SQLite are production code.
enum FixtureFiles { static let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraBackupChecks-\(UUID())") }
struct Meeting: Codable { var id = UUID(); var rawAudioReference: String?; var photoFileNames: [String]?; var legacyPhotoData: [Data]?; var audioURL: URL? { rawAudioReference.map { MediaFiles.directory.appendingPathComponent($0) } } }
struct MemoraSpace: Codable { var id = UUID() }
struct MemoraTask: Codable { var id = UUID() }
struct LifeLogEntry: Codable { var id = UUID(); var photoFileName: String? }
struct Person: Codable { var id = UUID() }
struct ProjectChatThread: Codable { var id = UUID(); var projectID: UUID? }
enum MediaFiles {
  static var directory: URL { FixtureFiles.root.appendingPathComponent("audio") }
  static var photosDirectory: URL { FixtureFiles.root.appendingPathComponent("photos") }
  static func isPlainName(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0") }
  static func reference(for url: URL) -> String? { isPlainName(url.lastPathComponent) && url.deletingLastPathComponent() == directory ? url.lastPathComponent : nil }
  static func photoURL(_ name: String) -> URL? { isPlainName(name) ? photosDirectory.appendingPathComponent(name) : nil }
  static func requiredPhotoFiles(for name: String) -> [String] { [name] }
  static func regenerablePhotoFiles(for name: String) -> [String] { [] }
}
enum ProjectSourceFiles {
  static var directory: URL { FixtureFiles.root.appendingPathComponent("workspace") }
  static let maximumFileBytes = 50 * 1024 * 1024
  static let maximumStorageBytes = 500 * 1024 * 1024
  enum Failure: Error { case capacity }
  static func resolve(_ name: String) -> URL? { MediaFiles.isPlainName(name) ? directory.appendingPathComponent(name) : nil }
}
