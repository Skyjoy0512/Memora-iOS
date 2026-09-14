import Foundation

struct MemoraTask: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var meetingID: UUID?
  var assignee: String?
  var dueDate: Date?
  var isCompleted: Bool
}
