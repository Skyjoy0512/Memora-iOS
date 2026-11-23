import SwiftUI

/// Pulling a conversation past its last message shows a spinner under it and,
/// at the limit, replaces it with a new chat — the gesture ChatGPT uses.
struct ConversationPullToNewChat: ViewModifier {
  var onNewChat: () -> Void

  @State private var pull: CGFloat = 0
  @State private var previousPull: CGFloat = 0
  @State private var bottomInset: CGFloat = 0

  /// How far past the last message the conversation has to be pulled.
  private let limit: CGFloat = 72

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Reading.self) { geometry in
        // The resting bottom is the natural scroll limit, or the top when the
        // conversation is shorter than the screen.
        let rest = max(-geometry.contentInsets.top,
          geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
        return Reading(pull: max(0, geometry.contentOffset.y - rest),
          bottomInset: geometry.contentInsets.bottom)
      } action: { _, reading in
        if bottomInset != reading.bottomInset { bottomInset = reading.bottomInset }
        let next = min(reading.pull, 160)
        if pull != next { pull = next }
        // Start once per gesture: the pull has to grow through the limit, so a
        // bounce that settles past it never starts a chat.
        let crossed = previousPull < limit && reading.pull >= limit
        previousPull = reading.pull
        guard crossed else { return }
        InteractionFeedback.shared.send(.selection)
        onNewChat()
      }
      .overlay(alignment: .bottom) {
        if pull > 0 {
          indicator
            .padding(.bottom, bottomInset + max(0, (min(pull, 120) - 56) / 2))
        }
      }
  }

  private var indicator: some View {
    VStack(spacing: MemoraSpacing.sm) {
      ProgressView()
        .controlSize(.regular)
      Text("新しいチャット")
        .font(.footnote)
        .foregroundStyle(MemoraPalette.textSecondary)
    }
    .opacity(Double(min(1, pull / 40)))
    .scaleEffect(0.9 + 0.1 * min(1, pull / limit))
    .frame(maxWidth: .infinity)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private struct Reading: Equatable {
    var pull: CGFloat
    var bottomInset: CGFloat
  }
}
