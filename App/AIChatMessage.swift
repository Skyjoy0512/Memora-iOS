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
  /// What the agent did on the way to this reply, in order.
  var agentSteps: [AgentStep] = []
  /// Documents the agent made in this reply.
  var documentIDs: [UUID] = []
  /// True while the reply is still being formed.
  var isThinking = false
  var createdAt = Date.now
  /// When the reply settled, for "4秒で回答".
  var finishedAt: Date?
  /// The words the records were searched with, shown at the top of the trace.
  var traceQuery: String?
  /// True for a reply the agent wrote, whose steps can change data.
  var isAgentReply = false
  /// The model's own reasoning, only when the provider returned it.
  var reasoning = ""
  /// True once the record search for an answer has finished.
  var searchFinished = false
  /// True once the person approved a change in this reply, so asking again
  /// could repeat it.
  var didChangeData = false
  /// The resident agent that posted this on its own, shown above the reply.
  var residentName: String?
  var residentSymbol: MemoraIcon?
  /// Next steps the resident agent proposed; sending one runs it as a normal
  /// request, with approval for any change.
  var suggestions: [String] = []

  /// How long the reply took, in whole seconds, once it has settled.
  var elapsedSeconds: Int? {
    finishedAt.map { max(1, Int($0.timeIntervalSince(createdAt).rounded())) }
  }
}
