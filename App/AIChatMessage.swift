import Foundation

/// One turn in the Ask AI chat.
struct AIChatMessage: Identifiable, Hashable {
  enum Role: Hashable {
    case user
    case assistant
  }

  var id = UUID()
  var role: Role
  var text: String
  /// The reasoning the answer is collapsed behind.
  var thinking: String?
  /// True while the reply is still being formed.
  var isThinking = false
  var createdAt = Date.now
}
