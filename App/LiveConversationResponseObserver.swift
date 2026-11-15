import SwiftUI

/// Only this leaf follows streamed answer text; the composer doesn't tick per token.
struct LiveConversationResponseObserver: View {
  @Environment(MemoraModel.self) private var model
  var session: LiveConversationSession

  var body: some View {
    let message = model.aiMessages.last { $0.id == session.responseID }
    let text = message?.text ?? ""
    let isThinking = message?.isThinking ?? true
    let waiting = model.pendingAgentApproval != nil || model.pendingAgentQuestions != nil
    Color.clear.frame(width: 0, height: 0)
      .onChange(of: text, initial: true) { _, _ in receive(message, waiting: waiting) }
      .onChange(of: isThinking) { _, _ in receive(message, waiting: waiting) }
      .onChange(of: session.responseID) { _, _ in receive(message, waiting: waiting) }
      .onChange(of: waiting) { _, _ in receive(message, waiting: waiting) }
      .accessibilityHidden(true)
  }

  private func receive(_ message: AIChatMessage?, waiting: Bool) {
    guard let message else { return }
    session.setAwaitingInteraction(waiting)
    // A partial structured block must never be spoken as JSON/code.
    let prose = message.isThinking ? String(message.text.components(separatedBy: "```").first ?? "") : message.text
    session.receiveResponse(id: message.id, speakableText: MemoraModel.spokenAnswerText(prose), isThinking: message.isThinking)
  }
}
