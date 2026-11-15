import SwiftUI

/// Only this leaf follows microphone levels; the chat history never ticks.
struct LiveMicrophoneMeter: View {
  var session: LiveConversationSession

  var body: some View {
    ProgressView(value: session.inputLevel)
      .progressViewStyle(.linear)
      .frame(width: 80)
      .tint(MemoraPalette.textSecondary)
      .opacity(session.isRunning ? 1 : 0)
      .accessibilityLabel("マイクの入力レベル")
      .accessibilityValue(session.inputLevel > 0.1 ? "音声を受信中" : "静かです")
      .accessibilityHidden(!session.isRunning)
  }
}
