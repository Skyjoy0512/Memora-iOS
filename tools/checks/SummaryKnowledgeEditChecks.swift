import Foundation
import SQLite3

@main
enum SummaryKnowledgeEditChecks {
  @MainActor static func main() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-fact-edit-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("store.sqlite")
    let model = MemoraModel(url: url)
    try model.store.prepare()
    let source = TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: 0, text: "公開日は承認後に決めます。")
    let fact = SummaryKnowledge.Fact(id: "f1", category: .decision, content: "公開日は承認後に決める", status: .confirmed,
      sourceReferences: [.init(sourceSegmentID: source.id.uuidString, quote: source.text)])
    var record = Meeting(id: UUID(), title: "本人のタイトル", createdAt: .now, duration: 60, source: .recording,
      status: .ready, summary: "本人の本文", keyPoints: [], decisions: [], openQuestions: [], transcript: [source])
    let version = TemplateSummary.snapshot(record: record, templateID: "market.regular", preferences: SummaryPreferences(),
      modelInfo: "fixture", knowledge: .init(facts: [fact]))
    record.summaryVersions = [version]; record.activeSummaryVersionID = version.id
    model.meetings = [record]
    precondition(model.saveSummaryFact(meetingID: record.id, versionID: version.id, original: fact,
      category: .decision, content: "公開日は本人が別途確認する", status: .pending))
    let updated = model.meetings[0]
    precondition(updated.summary == record.summary && updated.transcript == record.transcript && updated.privacy == record.privacy)
    precondition(updated.summaryVersions.count == 2 && updated.summaryVersions[0] == version)
    let authored = updated.activeSummaryVersion!.knowledge!.facts[0]
    precondition(authored.origin == .user && authored.status == .pending && authored.sourceReferences!.isEmpty)
    precondition(updated.currentSummaryKnowledge == nil)
    let reopened = LocalStore(fileURL: url); try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome("meetings") else { preconditionFailure("Missing record") }
    let persisted = try JSONDecoder().decode([Meeting].self, from: data)
    precondition(persisted == [updated])
    precondition(!model.saveSummaryFact(meetingID: record.id, versionID: version.id, original: fact,
      category: .decision, content: "古い画面からの編集", status: .confirmed))
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_fact BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.saveSummaryFact(meetingID: record.id, versionID: updated.activeSummaryVersionID!, original: authored,
      category: .decision, content: "保存に失敗する編集", status: .confirmed))
    precondition(model.meetings == [updated])
    precondition(!model.restoreSummary(version.id, meetingID: record.id))
    precondition(model.meetings == [updated] && model.announcements.isEmpty)
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_fact;", nil, nil, nil) == SQLITE_OK)
    precondition(model.restoreSummary(version.id, meetingID: record.id))
    precondition(model.meetings[0].activeSummaryVersionID == version.id)
    precondition(model.meetings[0].summaryVersions == updated.summaryVersions)
    precondition(model.meetings[0].transcript == updated.transcript && model.announcements.count == 1)
    model.currentTeamID = "team"
    precondition(!model.saveSummaryFact(meetingID: record.id, versionID: version.id, original: fact,
      category: .decision, content: "チームでは変更しない", status: .confirmed))
    model.currentTeamID = nil; model.processing.isBusy = true
    precondition(!model.saveSummaryFact(meetingID: record.id, versionID: version.id, original: fact,
      category: .decision, content: "生成中には変更しない", status: .confirmed))
    print("SummaryKnowledgeEditChecks: passed (production fact editor mutation + meeting commit, immutable prior history, no inherited proof, unchanged source/body/privacy, stale callback/busy/team refusal, real SQLite rollback and reopen; model state/media are fixtures)")
  }
}

@MainActor final class MemoraModel {
  var meetings: [Meeting] = []
  var store: LocalStore
  var currentTeamID: String?
  var isRestoring = false
  var isApplyingTransientMeetingUpdate = false
  var isStoreProtected = false
  var aiWorkspaceGeneration = UUID()
  var meetingSearchTexts: [UUID: String] = [:]
  var persistenceFailureMessage: String?
  var processing = ProcessingFixture()
  var summaryPreferences = SummaryPreferences()
  var announcements: [String] = []
  func announce(_ message: String) { announcements.append(message) }
  enum StorageKey { static let meetings = "meetings" }
  init(url: URL) { store = LocalStore(fileURL: url) }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistBatch(meetings: [Meeting]? = nil, prepared: [UUID: Data] = [:],
                    _ body: () throws -> [(key: String, data: Data)]) -> Bool {
    do {
      var writes = try body()
      if let meetings { writes.append((key: "meetings", data: try RecordStore.encoded(meetings))) }
      try store.applyBatch(writes: writes, removing: [])
      return true
    } catch { return false }
  }
}
struct ProcessingFixture {
  var isBusy = false
  func isActive(_ id: UUID) -> Bool { isBusy }
}
enum RecordStore { static func encoded<Value: Encodable>(_ value: Value) throws -> Data { try JSONEncoder().encode(value) } }
enum MediaFiles {
  static func resolve(_ value: String) -> URL? { nil }
  static func reference(for url: URL) -> String? { nil }
  static func writePhoto(_ data: Data) -> String? { nil }
  static func deletePhoto(_ name: String) {}
}
