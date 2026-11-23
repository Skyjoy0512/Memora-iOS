import SwiftUI

/// Keep per-token observation and animation out of the transcript layout.
struct AskAIGlow: View {
  @Environment(MemoraModel.self) private var model
  var isVisible: Bool
  @State private var phase = AskAIAuroraPhase()
  @State private var lastReplyID: UUID?

  var body: some View {
    let signal = signal
    Color.clear
      .overlay {
        if isVisible, model.selectedTab == .askAI, !model.isToolsPresented {
          MemoraAuroraBackground(isThinking: phase.isThinking(signal))
            .id(signal.replyID ?? lastReplyID)
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onChange(of: model.aiConversationID) { _, _ in lastReplyID = nil }
      .onChange(of: signal, initial: true) { _, signal in
        if let replyID = signal.replyID { lastReplyID = replyID }
        phase.update(signal)
      }
  }

  private var signal: AskAIAuroraPhase.Signal {
    guard model.isAIChatResponding,
          let reply = model.aiMessages.last(where: { $0.role == .assistant && $0.residentName == nil }),
          reply.isThinking else { return .init(replyID: nil) }
    return .init(replyID: reply.id, hasText: !reply.text.isEmpty,
      isWaitingForPerson: model.pendingAgentApproval?.messageID == reply.id || model.pendingAgentQuestions?.messageID == reply.id)
  }
}
