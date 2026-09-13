import Foundation

struct AIConversationEntry: Identifiable, Hashable {
  var id: UUID
  var question: String
  var answer: String
  var scopeLabel: String
  var createdAt: Date
}
