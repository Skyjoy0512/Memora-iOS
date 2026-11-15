import Foundation
import SQLite3

// Production generation, validation, snapshot and atomic writer; only engines
// and the model container are fixtures. No network, credentials or model fees.
@MainActor final class MemoraModel {
  var meetings: [Meeting] = []
  var store: LocalStore
  var meetingSearchTexts: [UUID: String] = [:]
  var aiWorkspaceGeneration = UUID()
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var persistenceFailureMessage: String?
  var activeDetailMeetingID: UUID?
  var activeDetailTabs = [0]
  var selectedTab = 0
  var activeProjectChatID: UUID?
  var composerDraft = ""
  var composerAttachment: String?
  var composerMentions: [String] = []
  var composerFocusRequest: UUID?
  var isAIChatResponding = false
  enum StorageKey { static let meetings = "memoraMeetings" }
  init(url: URL) throws { store = LocalStore(fileURL: url); try store.prepare() }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    !isRestoring && !isStoreProtected && meeting(id: id).map { RecordAccessPolicy.allows($0.privacy, purpose: purpose) } == true
  }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistMeetings() { _ = persistBatch { [(StorageKey.meetings, try RecordStore.encoded(meetings))] } }
  func persistBatch(_ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do { try store.applyBatch(writes: try build(), removing: []); return true } catch { return false }
  }
}
struct Meeting: Codable, Equatable {
  var id = UUID()
  var title = "図解テスト"
  var displayTitle: String { title }
  var createdAt = Date(timeIntervalSince1970: 0)
  var duration = 0.0
  enum Source: Codable { case importFile }
  var source = Source.importFile
  enum Status: Codable { case ready }
  var status = Status.ready
  var summary = "## 決定事項\n- 先に5人で検証し、結果を見て公開日を決める\n## 未解決事項\n- 公開日は未定"
  var keyPoints: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var summaryInfographicJSON: String?
  var privacy = RecordPrivacy()
  var effectivePrivacy: RecordPrivacy { privacy }
  var transcript: [TranscriptSegment] = []
  var notes = ""
}
enum RecordStore {
  static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}
enum AIEngine { case cloud, foundation }
enum ContextTaskKind { case chat }
struct LLMSelection { var modelLabel = "Fixture・実モデル未実行" }
struct AIAnswerFailure { var message = "Fixture error" }
enum AIAnswerResult {
  case answer(String), failure(AIAnswerFailure)
  var text: String? { if case .answer(let text) = self { return text }; return nil }
  var failure: AIAnswerFailure? { if case .failure(let failure) = self { return failure }; return nil }
}
@MainActor enum AIEngineService {
  static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine }
  static func contextCharacterLimit(for engine: AIEngine, llm: LLMSelection? = nil,
                                    task: ContextTaskKind = .chat) -> Int { 40_000 }
  static func answer(engine: AIEngine, llm: LLMSelection, question: String, scopeLabel: String, context: String, history: String) async -> AIAnswerResult {
    .failure(.init())
  }
}
@MainActor enum CloudAIService {
  static var response = ""
  static var calls = 0
  static var onCall: (() -> Void)?
  static func complete(system: String, user: String, llm: LLMSelection, maximumOutputTokens: Int?, authorize: (@MainActor () -> Bool)? = nil) async -> AIAnswerResult {
    precondition(system == MeetingInfographicPrompt.system && maximumOutputTokens == 4_200)
    calls += 1
    onCall?()
    return .answer(response)
  }
}

@main enum MeetingInfographicChecks {
  @MainActor static func main() async throws {
    for (claim, evidence, accepted) in [
      ("50人", "150人", false), ("500円", "1,500円", false), ("10%", "110%", false),
      ("50人", "50円", false), ("10%", "10人", false), ("1時間", "1時", false),
      ("-5%", "+5%", false), ("2026/10/25", "2026/10/24", false),
      ("5月1日", "5月11日", false), ("10:30", "11:30", false),
      ("1,500円", "1500円", true), ("1500円", "１，５００円", true),
      ("50%", "50パーセント", true), ("150,50円", "150,50円", false),
      ("20GWh", "20MWh", false), ("100USD", "100JPY", false), ("50匹", "50頭", false),
      ("10月28日", "| 田中 | 10月28日 |", true), ("2026/10/25", "日付は 2026/10/25 です", true),
      ("5%", "- 5%", false), ("-5%", "- 5%", true),
      ("¥5", "-¥5", false), ("$5", "+$5", false), ("-¥5", "- ¥5", true)
    ] { precondition(GroundedQuantity.supports(claim, in: evidence) == accepted, "Quantity evidence mismatch: \(claim)") }
    for (claim, evidence, accepted) in [
      ("50人", "承認された場合は50人", false), ("50人", "50人増加しない", false),
      ("50人増加しない", "50人増加しない", true), ("50人", "50人の予定", false),
      ("50人から100人へ減少", "50人から100人へ増加", false),
      ("10万円", "10万円ではなく12万円", false),
      ("10万円ではなく12万円", "10万円ではなく12万円", true),
      ("50人", "50人以外", false), ("50人", "50人を除く", false),
      ("承認済み", "未承認", false), ("実施", "未実施", false)
    ] { precondition(GroundedQuantity.preservesQualification(claim, in: evidence) == accepted) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("infographic-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try MemoraModel(url: root.appendingPathComponent("records.sqlite"))
    let displaySample = SummarizedAudioSample.make()
    model.meetings = [displaySample]
    let displaySource = displaySample.summary.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    for claim in [MeetingInfographicSample.content.headline] + MeetingInfographicSample.content.panels.flatMap(\.items) {
      if !displaySource.contains(claim.evidence) { print("Sample quote mismatch: \(claim.label)") }
      if !GroundedQuantity.supports(claim.label + " " + claim.text, in: claim.evidence) { print("Sample quantity mismatch: \(claim.label)") }
      if !GroundedQuantity.preservesQualification(claim.text, in: claim.evidence) { print("Sample qualification mismatch: \(claim.label)") }
      if !GroundedQuantity.preservesQualification(claim.label, in: claim.evidence, considersEvidence: false) { print("Sample label mismatch: \(claim.label)") }
    }
    guard let displaySnapshot = MeetingSummaryPosterSnapshot(meetingID: displaySample.id, model: model),
          MeetingInfographicSample.resolve(displaySnapshot) != nil else {
      print("FAIL: production display sample no longer satisfies evidence validation")
      exit(1)
    }
    let record = Meeting()
    model.meetings = [record]
    model.activeDetailMeetingID = record.id
    let config = (engine: AIEngine.cloud, llm: LLMSelection())
    let claim = MeetingInfographic.Claim(label: "検証人数", text: "5人", evidence: "先に5人で検証し、結果を見て公開日を決める")
    let content = MeetingInfographic.Content(headline: claim,
      panels: [.init(title: "検証してから判断", kind: .metric, items: [claim])],
      questions: ["公開判断に必要な確認は？", "検証の準備を整理して", "未確定事項は何？"])
    CloudAIService.response = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
    func snapshot() -> MeetingSummaryPosterSnapshot { MeetingSummaryPosterSnapshot(meetingID: record.id, model: model)! }
    do { try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: false); preconditionFailure("Consent bypass") } catch {}
    precondition(CloudAIService.calls == 0)
    try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: true)
    precondition(CloudAIService.calls == 1)
    let saved = model.meetings[0].summaryInfographicJSON!
    let document = MeetingInfographicSample.resolve(snapshot())!
    precondition(document.content == content && document.sourceSummary == record.summary)
    let reopened = LocalStore(fileURL: root.appendingPathComponent("records.sqlite"))
    try reopened.prepare()
    guard case .data(let bytes) = reopened.readOutcome(MemoraModel.StorageKey.meetings) else { fatalError("Missing SQLite result") }
    let reopenedMeetings = try JSONDecoder().decode([Meeting].self, from: bytes)
    precondition(reopenedMeetings[0].summaryInfographicJSON == saved)
    var invalid = content
    invalid.panels[0].items[0].text = "50人"
    do { try invalid.validate(against: record.summary); preconditionFailure("Invented number") } catch {}
    invalid = content; invalid.headline.evidence = "根拠を創作しました"
    do { try invalid.validate(against: record.summary); preconditionFailure("Invented evidence") } catch {}
    invalid = content; invalid.questions = ["同じ", "同じ", "同じ"]
    do { try invalid.validate(against: record.summary); preconditionFailure("Duplicate questions") } catch {}
    invalid = content; invalid.panels += invalid.panels
    do { try invalid.validate(against: record.summary); preconditionFailure("Duplicate panel identity") } catch {}
    invalid = content; invalid.panels[0].items[0].text = "改行\n\n\n\nで画像を引き延ばす"
    do { try invalid.validate(against: record.summary); preconditionFailure("Unbounded vertical layout") } catch {}
    invalid = content; invalid.panels[0].items[0].text = String(repeating: "長", count: 49)
    do { try invalid.validate(against: record.summary); preconditionFailure("Oversized panel text") } catch {}
    CloudAIService.response = "not JSON"
    do { try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: true); preconditionFailure("Bad JSON saved") } catch {}
    precondition(model.meetings[0].summaryInfographicJSON == saved)
    CloudAIService.response = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
    var connection: OpaquePointer?
    precondition(sqlite3_open(root.appendingPathComponent("records.sqlite").path, &connection) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    precondition(sqlite3_exec(connection, "CREATE TRIGGER fail_diagram BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    do { try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: true); preconditionFailure("Failed save reported as success") } catch {}
    precondition(model.meetings[0].summaryInfographicJSON == saved)
    precondition(sqlite3_exec(connection, "DROP TRIGGER fail_diagram;", nil, nil, nil) == SQLITE_OK)
    CloudAIService.onCall = { model.meetings[0].privacy.allowsCloudAI.toggle() }
    do { try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: true); preconditionFailure("Privacy race saved") } catch {}
    precondition(model.meetings[0].summaryInfographicJSON == saved && MeetingInfographicSample.resolve(snapshot()) == nil)
    model.meetings[0].privacy = record.privacy
    CloudAIService.onCall = { model.aiWorkspaceGeneration = UUID() }
    do { try await model.generateMeetingInfographic(snapshot(), configuration: config, cloudConsent: true); preconditionFailure("Workspace race saved") } catch {}
    CloudAIService.onCall = nil
    let current = snapshot()
    precondition(!model.stageMeetingQuestion("unknown", snapshot: current))
    precondition(model.stageMeetingQuestion(content.questions[0], snapshot: current))
    precondition(model.composerDraft == content.questions[0] && model.composerFocusRequest != nil)
    precondition(!model.stageMeetingQuestion(content.questions[1], snapshot: current))
    model.composerDraft = ""; model.composerAttachment = "attachment"
    precondition(!model.stageMeetingQuestion(content.questions[1], snapshot: current))
    model.composerAttachment = nil; model.composerMentions = ["mention"]
    precondition(!model.stageMeetingQuestion(content.questions[1], snapshot: current))
    model.composerMentions = []; model.meetings[0].summary += "\n変更"
    precondition(!model.stageMeetingQuestion(content.questions[1], snapshot: current))
    precondition(MeetingInfographicSample.resolve(snapshot()) == nil)
    print("Infographic checks passed: production generation → validated interpretation → SQLite → reopen; consent, invalid JSON, invented number/evidence, duplicate IDs, save failure, privacy/workspace race, stale source and draft/attachment/mention protection")
  }
}
