import Foundation

@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var aiPersonScopeID: UUID?
  var isRestoring = false
  var isStoreProtected = false
  var aiMessages: [String] = []
  var isAIChatResponding = false
  var composerDraft = ""
  var composerAttachment: String?
  var composerFocusRequest: UUID?
  var meetings: [Meeting] = []
  var tasks: [MemoraTask] = []

  func sendAIChat(_ prompt: String) -> Bool {
    aiMessages.append(prompt)
    return true
  }

  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected, let record = meetings.first(where: { $0.id == id }) else { return false }
    return RecordAccessPolicy.allows(record.privacy, purpose: purpose)
  }
  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool {
    RecordAccessPolicy.allowsRelated(task.privacy, parentID: task.meetingID,
      parentPrivacy: meetings.first { $0.id == task.meetingID }?.privacy, purpose: purpose, inheritsParent: true)
  }
}

struct Meeting {
  var id = UUID()
  var title: String
  var createdAt: Date
  var transcript = ["Fixture transcript"]
  var notes = ""
  var status = Status.ready
  var summary = "Fixture summary"
  var privacy = RecordPrivacy()
  var displayTitle: String { title }
  enum Status { case ready, recording }
}

enum SampleContent {
  static let sampleID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  static func isSample(meetingID: UUID) -> Bool { meetingID == sampleID }
  static func isSample(task: MemoraTask) -> Bool { task.id == sampleID }
}
