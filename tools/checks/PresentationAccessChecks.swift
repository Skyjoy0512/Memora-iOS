import Foundation

// The production collection extension runs against a small in-memory archive.
// Access decisions stand in for the existing privacy subsystem; no provider runs.
@MainActor final class MemoraModel {
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var meetings: [Meeting] = []
  var tasks: [FixtureTask] = []
  var documents: [MemoraDocument] = []
  var people: [FixturePerson] = []
  var isAIMemoryEnabled = false
  var visibleAIMemories: [FixtureMemory] = []
  var lifeLogEntries: [FixtureJournal] = []
  var allowed: Set<RecordPrivacyTarget> = []
  var askAIConfiguration: (engine: Bool, llm: Bool) { (true, true) }
  func space(id: UUID) -> FixtureSpace? { .init(name: "販売システム") }
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool { allowed.contains(.meeting(id)) }
  func allowsRecordAccess(_ target: RecordPrivacyTarget, purpose: RecordAccessPolicy.Purpose) -> Bool { allowed.contains(target) }
  func allowsTaskAccess(_ task: FixtureTask, purpose: RecordAccessPolicy.Purpose) -> Bool { allowed.contains(.task(task.id)) }
  func allowsPersonAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool { allowed.contains(.person(id)) }
  func allowsJournalAccess(_ entry: FixtureJournal, purpose: RecordAccessPolicy.Purpose) -> Bool { allowed.contains(.journal(entry.id)) }
}

enum RecordAccessPolicy { enum Purpose { case cloudAI, onDeviceAI } }
enum ContextTaskKind { case presentation }
enum AIEngineService {
  static func contextCharacterLimit(for engine: Bool, llm: Bool, task: ContextTaskKind) -> Int { 80_000 }
}
struct FixtureSpace { var name: String }
struct FixturePrivacy { var allowsCloudAI = true }
struct TranscriptSegment { var speaker: String; var text: String }
struct Meeting {
  var id = UUID()
  var displayTitle = "販売システム"
  var spaceID: UUID?
  var summary = "販売システムの売上は100万円。"
  var keyPoints: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var notes = ""
  var transcript: [TranscriptSegment] = []
  var effectivePrivacy = FixturePrivacy()
  var createdAt = Date.now
  var participantIDs: [UUID]?
  var status = Status.ready
  enum Status { case ready }
}
struct FixtureTask {
  var id = UUID()
  var title: String
  var detail = ""
  var assignee: String?
  var dueDate: Date?
  var workDate: Date?
  var completedAt: Date?
  var isCompleted = false
  var meetingID: UUID?
  var relationships = Relationships()
  struct Relationships { var assigneePersonID: UUID? }
}
struct FixturePerson { var id = UUID(); var name = "田中" }
struct FixtureMemory {
  var id = UUID(); var text = ""; var updatedAt = Date.now; var status = Status.current
  enum Status { case current }
}
struct FixtureJournal {
  var id = UUID(); var title = "販売システムのジャーナル"; var summary = "非公開の記録"
  var occurredAt = Date.now; var createdAt = Date.now
}

@main struct PresentationAccessChecks {
  @MainActor static func main() {
    let model = MemoraModel()
    precondition(MemoraModel.presentationDecisionStatus("中止案は未承認") == .open)
    precondition(MemoraModel.presentationDecisionStatus("予算を保留") == .open)
    let project = UUID()
    let person = FixturePerson()
    var meeting = Meeting(spaceID: project)
    meeting.participantIDs = [person.id]
    meeting.transcript = [.init(speaker: "田中", text: "販売の承認を依頼"), .init(speaker: "田中 太郎", text: "他人の発言")]
    let otherMeeting = Meeting(spaceID: UUID(), summary: "別プロジェクトの販売会議")
    var permitted = FixtureTask(title: "販売の公開タスク", meetingID: meeting.id)
    permitted.relationships.assigneePersonID = person.id
    var denied = FixtureTask(title: "販売の非公開タスク", meetingID: meeting.id)
    denied.relationships.assigneePersonID = person.id
    let outside = FixtureTask(title: "販売の範囲外タスク", meetingID: otherMeeting.id)
    let journal = FixtureJournal()
    model.people = [person]
    model.meetings = [meeting, otherMeeting]
    model.tasks = [permitted, denied, outside]
    model.lifeLogEntries = [journal]
    model.documents = [.init(title: "販売システムの非公開資料", kind: .document, markdown: "非公開本文")]
    model.allowed = [.meeting(meeting.id), .meeting(otherMeeting.id), .task(permitted.id), .task(outside.id), .person(person.id)]
    func pack(projectID: UUID? = nil) -> PresentationEvidencePack {
      model.presentationEvidencePack(query: "販売 田中 タスク", purpose: "販売の報告", projectID: projectID)
    }
    let scoped = pack(projectID: project)
    let scopedText = scoped.render()
    precondition(!scopedText.contains("非公開タスク") && !scopedText.contains("範囲外タスク"))
    precondition(!scopedText.contains("非公開資料") && !scopedText.contains("非公開本文"))
    let personFact = scoped.keyFacts.first { $0.sourceID == "person:\(person.id.uuidString)" }!
    precondition(personFact.text.contains("販売の公開タスク") && !personFact.text.contains("他人の発言"))
    let targets = Set(model.presentationEvidenceReadTargets(scoped))
    precondition(targets.contains(.task(permitted.id)) && targets.contains(.person(person.id)) && targets.contains(.meeting(meeting.id)))
    precondition(!targets.contains(.task(denied.id)) && !targets.contains(.task(outside.id)))
    let personReference = scoped.relatedSources.first { $0.id == "person:\(person.id.uuidString)" }!
    precondition(model.presentationEvidenceSourceAllowsCloud(personReference))
    model.allowed.remove(.task(permitted.id))
    precondition(!model.presentationEvidenceSourceAllowsCloud(personReference), "Dependency revocation must invalidate the saved person source")
    model.allowed.insert(.task(permitted.id))
    precondition(!pack().render().contains("非公開の記録"), "Journal permission must include its parent and data kind")
    model.people.append(.init(name: "田中"))
    let ambiguous = pack(projectID: project).keyFacts.first { $0.sourceID == "person:\(person.id.uuidString)" }!
    precondition(!ambiguous.text.contains("発言:"), "Same-name speakers must not be attributed to both people")
    model.isStoreProtected = true
    precondition(pack().keyFacts.isEmpty)
    model.isStoreProtected = false; model.currentTeamID = "team"
    precondition(pack().keyFacts.isEmpty)
    print("Presentation access passed: production collector, task/project permissions, person dependencies, exact/ambiguous speaker names, journal gate, local-only documents, protected store and workspace")
  }
}
