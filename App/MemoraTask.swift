import Foundation

struct MemoraTask: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var detail: String = ""
  var workDate: Date?
  var progress: TaskProgress = .notStarted
  var meetingID: UUID?
  var assignee: String?
  var dueDate: Date?
  var isCompleted: Bool
  /// When it was completed, so the completed list can be ordered by it.
  var completedAt: Date?
  /// Whether a reminder is wanted on the due date.
  var remindsAtDue: Bool
  /// The time of day the reminder fires. nil means the default, 9:00.
  var reminderTime: Date?

  init(
    id: UUID,
    title: String,
    meetingID: UUID? = nil,
    assignee: String? = nil,
    dueDate: Date? = nil,
    isCompleted: Bool,
    detail: String = "",
    workDate: Date? = nil,
    progress: TaskProgress = .notStarted,
    completedAt: Date? = nil,
    remindsAtDue: Bool = false,
    reminderTime: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.workDate = workDate
    self.progress = progress
    self.meetingID = meetingID
    self.assignee = assignee
    self.dueDate = dueDate
    self.isCompleted = isCompleted
    self.completedAt = completedAt
    self.remindsAtDue = remindsAtDue
    self.reminderTime = reminderTime
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, detail, workDate, progress, meetingID, assignee, dueDate, isCompleted, completedAt, remindsAtDue, reminderTime
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
    workDate = try container.decodeIfPresent(Date.self, forKey: .workDate)
    progress = try container.decodeIfPresent(TaskProgress.self, forKey: .progress) ?? .notStarted
    meetingID = try container.decodeIfPresent(UUID.self, forKey: .meetingID)
    assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
    dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
    completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    remindsAtDue = try container.decodeIfPresent(Bool.self, forKey: .remindsAtDue) ?? false
    reminderTime = try container.decodeIfPresent(Date.self, forKey: .reminderTime)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(detail, forKey: .detail)
    try container.encodeIfPresent(workDate, forKey: .workDate)
    try container.encode(progress, forKey: .progress)
    try container.encodeIfPresent(meetingID, forKey: .meetingID)
    try container.encodeIfPresent(assignee, forKey: .assignee)
    try container.encodeIfPresent(dueDate, forKey: .dueDate)
    try container.encode(isCompleted, forKey: .isCompleted)
    try container.encodeIfPresent(completedAt, forKey: .completedAt)
    try container.encode(remindsAtDue, forKey: .remindsAtDue)
    try container.encodeIfPresent(reminderTime, forKey: .reminderTime)
  }
}
