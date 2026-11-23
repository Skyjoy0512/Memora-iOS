import Foundation

struct AskAIAuroraPhase {
  private var replyID: UUID?
  private var hasStartedAnswer = false

  mutating func update(_ signal: Signal) {
    if replyID != signal.replyID {
      replyID = signal.replyID
      hasStartedAnswer = false
    }
    hasStartedAnswer = hasStartedAnswer || signal.hasText
  }

  func isThinking(_ signal: Signal) -> Bool {
    signal.replyID != nil && !signal.hasText && !signal.isWaitingForPerson
      && (signal.replyID != replyID || !hasStartedAnswer)
  }

  struct Signal: Equatable {
    var replyID: UUID?
    var hasText = false
    var isWaitingForPerson = false
  }
}
