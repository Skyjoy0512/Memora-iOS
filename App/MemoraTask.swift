import Foundation

struct MemoraTask: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var meetingID: UUID?
  var assignee: String?
  var dueDate: Date?
  var isCompleted: Bool
  /// When it was completed, so the completed list can be ordered by it.
  var completedAt: Date?
  /// Whether a reminder is wanted on the due date.
  var remindsAtDue: Bool

  init(
    id: UUID,
    title: String,
    meetingID: UUID? = nil,
    assignee: String? = nil,
    dueDate: Date? = nil,
    isCompleted: Bool,
    completedAt: Date? = nil,
    remindsAtDue: Bool = false
  ) {
    self.id = id
    self.title = title
    self.meetingID = meetingID
    self.assignee = assignee
    self.dueDate = dueDate
    self.isCompleted = isCompleted
    self.completedAt = completedAt
    self.remindsAtDue = remindsAtDue
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, meetingID, assignee, dueDate, isCompleted, completedAt, remindsAtDue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    meetingID = try container.decodeIfPresent(UUID.self, forKey: .meetingID)
    assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
    dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
    completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    remindsAtDue = try container.decodeIfPresent(Bool.self, forKey: .remindsAtDue) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(meetingID, forKey: .meetingID)
    try container.encodeIfPresent(assignee, forKey: .assignee)
    try container.encodeIfPresent(dueDate, forKey: .dueDate)
    try container.encode(isCompleted, forKey: .isCompleted)
    try container.encodeIfPresent(completedAt, forKey: .completedAt)
    try container.encode(remindsAtDue, forKey: .remindsAtDue)
  }
}
