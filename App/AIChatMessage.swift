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
  /// What produced the answer: the scope, engine, model, and time. Shown
  /// instead of an invented reasoning trace.
  var details: AIAnswerDetails?
  /// The records the answer was built from. Empty when nothing grounded it,
  /// such as the fallback shown when no engine can run.
  var sources: [AIChatSource] = []
  /// True while the reply is still being formed.
  var isThinking = false
  var createdAt = Date.now
}
