import Foundation
import SQLite3

@main @MainActor
struct ComposerRecoveryChecks {
  static var storeURL: URL { URL(fileURLWithPath: CommandLine.arguments[1]) }
  static var questionKey: String { DraftStore.storageKey(for: ComposerDraftStore.questionKey) }
  static var mentionsKey: String { DraftStore.storageKey(for: ComposerDraftStore.mentionsKey) }
  static var attachmentKey: String { DraftStore.storageKey(for: ComposerDraftStore.attachmentKey) }
  static var indexKey: String { ComposerDraftStore.recoveryIndexKey }

  static func main() async throws {
    try LocalStore.shared.prepare()
    try RecordStore.saveDataNow(Data("actual-record".utf8), key: "fixture.business-record")
    let directory = storeURL.deletingLastPathComponent().appendingPathComponent("AIAttachments")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("safe.pdf")
    try Data("fixture".utf8).write(to: file)
    let attachment = AIAttachmentFileReference(AIAttachment(id: UUID(), name: "資料", url: file))!
    let encodedReference = String(decoding: try JSONEncoder().encode(attachment), as: UTF8.self)
    let bad = Data([1, 255, 254])
    let question = "本文 [@カレンダー]"
    let mention = ComposerMention(pluginID: "service:calendar", label: "カレンダー", range: (question as NSString).range(of: "[@カレンダー]"))
    try DraftStore.saveAndWait(question, key: ComposerDraftStore.questionKey)
    try DraftStore.saveAndWait(String(decoding: JSONEncoder().encode([mention]), as: UTF8.self), key: ComposerDraftStore.mentionsKey)
    try DraftStore.saveAndWait(encodedReference, key: ComposerDraftStore.attachmentKey)
    let healthy = try ComposerDraftStore.load()
    precondition(healthy.question == question && healthy.mentions == [mention] && healthy.attachment == attachment)
    try RecordStore.saveDataNow(JSONEncoder().encode(question), key: questionKey)
    expect(try ComposerDraftStore.load().question == question)
    let beforeHealthy = try database()
    _ = try ComposerDraftStore.recover()
    expect(try database() == beforeHealthy, "A healthy draft created an unnecessary archive")

    for (key, bytes) in [(questionKey, bad), (mentionsKey, bad), (attachmentKey, bad),
                         (mentionsKey, DraftStore.encode("{invalid json}")),
                         (attachmentKey, DraftStore.encode("{invalid json}"))] {
      try RecordStore.saveDataNow(bytes, key: key)
      try unreadable()
      let originalFields = try rawFields()
      let recovered = try ComposerDraftStore.recover()
      let references = try ComposerDraftStore.recoveryArchives()
      let archive = try JSONDecoder().decode(ComposerDraftRecoveryArchive.self, from: ComposerDraftStore.archiveData(references[0]))
      precondition(archive.fields == originalFields && archive.version == 1)
      let loaded = try ComposerDraftStore.load()
      precondition(loaded.question == recovered.question && loaded.mentions == recovered.mentions && loaded.attachment == recovered.attachment)
      expect(try data("fixture.business-record") == Data("actual-record".utf8))
      let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
      guard case .data(let durable) = reopened.readOutcome(questionKey) else { preconditionFailure() }
      precondition(DraftStore.decode(durable) == recovered.question)
      // Seed the next case without replacing any archived data.
      try DraftStore.saveAndWait(question, key: ComposerDraftStore.questionKey)
      try DraftStore.saveAndWait("[]", key: ComposerDraftStore.mentionsKey)
      try DraftStore.saveAndWait(encodedReference, key: ComposerDraftStore.attachmentKey)
    }
    let keptArchives = try ComposerDraftStore.recoveryArchives()
    precondition(keptArchives.count == 5)
    let firstBytes = try ComposerDraftStore.archiveData(keptArchives.last!)

    // Rejection at every transaction stage leaves the entire database unchanged.
    for phase in 0..<6 {
      try RecordStore.saveDataNow(bad, key: questionKey)
      if phase == 5 { try RecordStore.saveDataNow(bad, key: attachmentKey) }
      else { try RecordStore.saveDataNow(DraftStore.encode(encodedReference), key: attachmentKey) }
      let before = try database()
      let sql: String
      switch phase {
      case 0: sql = "CREATE TRIGGER reject_repair BEFORE INSERT ON documents WHEN NEW.key LIKE 'draft.composer.recovery.%' AND NEW.key != '\(indexKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      case 1: sql = "CREATE TRIGGER reject_repair BEFORE INSERT ON documents WHEN NEW.key = '\(indexKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      case 2: sql = "CREATE TRIGGER reject_repair BEFORE INSERT ON documents WHEN NEW.key = '\(questionKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      case 3: sql = "CREATE TRIGGER reject_repair BEFORE INSERT ON documents WHEN NEW.key = '\(mentionsKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      case 4: sql = "CREATE TRIGGER reject_repair BEFORE INSERT ON documents WHEN NEW.key = '\(attachmentKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      default: sql = "CREATE TRIGGER reject_repair BEFORE DELETE ON documents WHEN OLD.key = '\(attachmentKey)' BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
      }
      try execute(sql)
      do { _ = try ComposerDraftStore.recover(); preconditionFailure("A rejected repair succeeded") } catch {}
      try execute("DROP TRIGGER reject_repair;")
      expect(try database() == before, "Failed recovery partially changed the database")
      try unreadable()
    }
    expect(try ComposerDraftStore.archiveData(keptArchives.last!) == firstBytes)

    // An unreadable archive index cannot be replaced with an empty index.
    let originalIndex = try data(indexKey)
    try RecordStore.saveDataNow(bad, key: indexKey)
    let beforeIndexFailure = try database()
    do { _ = try ComposerDraftStore.recover(); preconditionFailure() }
    catch ComposerDraftStore.Failure.archiveUnreadable {}
    expect(try database() == beforeIndexFailure)
    try RecordStore.saveDataNow(originalIndex, key: indexKey)
    _ = try ComposerDraftStore.recover()

    // Latest queued input, not older committed text, is what the repair preserves.
    try RecordStore.saveDataNow(bad, key: mentionsKey)
    try DraftStore.saveAndWait("古い本文", key: ComposerDraftStore.questionKey)
    DraftStore.save("まだ保存待ちの本文", key: ComposerDraftStore.questionKey)
    let latest = try ComposerDraftStore.recover()
    precondition(latest.question == "まだ保存待ちの本文")
    await RecordStore.flushAsync()
    expect(try ComposerDraftStore.load().question == latest.question)

    // Read-only workspace/store/restore and live reply guards never lift record protection.
    for mode in 0..<5 {
      try RecordStore.saveDataNow(bad, key: mentionsKey)
      let model = MemoraModel()
      switch mode {
      case 0: model.currentTeamID = "team"
      case 1: model.isStoreProtected = true
      case 2: model.isRestoring = true
      case 3: model.isAIChatResponding = true
      default: model.composerDraftFailure = .unavailable
      }
      let before = try database()
      do { try model.recoverComposerDraft(); preconditionFailure() } catch {}
      expect(try database() == before && model.composerDraftFailure != nil)
      precondition(model.isStoreProtected == (mode == 1))
    }
    let model = MemoraModel()
    try model.recoverComposerDraft()
    precondition(model.composerDraftFailure == nil && model.composerDraft == latest.question && !model.isStoreProtected)
    expect(try data("fixture.business-record") == Data("actual-record".utf8))

    // Real SQLite read failures stay distinguishable from malformed draft bytes.
    try execute("DROP TABLE documents;")
    do { _ = try ComposerDraftStore.load(); preconditionFailure() }
    catch ComposerDraftStore.Failure.unavailable {}
    do { _ = try ComposerDraftStore.recover(); preconditionFailure() }
    catch ComposerDraftStore.Failure.unavailable {}
    print("PASS: production composer decoding/recovery/model guards/RecordStore + real SQLite; legacy/marked data, text/mention/attachment corruption, exact byte archives, 6 transaction rollback stages, damaged index refusal, queued latest input, restart reads, unrelated record preservation and read-failure distinction. Singleton/media paths are isolated; no user data.")
  }

  static func unreadable() throws {
    do { _ = try ComposerDraftStore.load(); preconditionFailure("Corrupt draft was accepted") }
    catch ComposerDraftStore.Failure.unreadable {}
  }
  static func rawFields() throws -> [String: Data] {
    var result: [String: Data] = [:]
    for key in [ComposerDraftStore.questionKey, ComposerDraftStore.mentionsKey, ComposerDraftStore.attachmentKey] {
      if case .data(let value) = RecordStore.loadLatestData(DraftStore.storageKey(for: key)) { result[key] = value }
    }
    return result
  }
  static func data(_ key: String) throws -> Data {
    guard case .data(let value) = RecordStore.load(key) else { throw ComposerDraftStore.Failure.unavailable }
    return value
  }
  static func execute(_ sql: String) throws {
    var connection: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &connection) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    precondition(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
  }
  static func database() throws -> [String: Data] {
    var connection: OpaquePointer?; var query: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &connection) == SQLITE_OK)
    defer { sqlite3_finalize(query); sqlite3_close(connection) }
    precondition(sqlite3_prepare_v2(connection, "SELECT key, data FROM documents;", -1, &query, nil) == SQLITE_OK)
    var result: [String: Data] = [:]
    while sqlite3_step(query) == SQLITE_ROW {
      let key = String(cString: sqlite3_column_text(query, 0))
      result[key] = Data(bytes: sqlite3_column_blob(query, 1), count: Int(sqlite3_column_bytes(query, 1)))
    }
    return result
  }
}

@MainActor final class MemoraModel {
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var isAIChatResponding = false
  var composerDraftFailure: ComposerDraftStore.Failure? = .unreadable
  var composerDraft = ""
  var composerMentions: [ComposerMention] = []
  var composerAttachment: AIAttachment?
}

func expect(_ value: Bool, _ message: String = "") { precondition(value, message) }
