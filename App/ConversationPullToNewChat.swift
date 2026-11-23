import SwiftUI

/// Pulling a conversation past its top edge shows a spinner and, at the
/// limit, replaces it with a new chat — the same gesture ChatGPT uses.
struct ConversationPullToNewChat: ViewModifier {
  var onNewChat: () -> Void

  @State private var pull: CGFloat = 0
  @State private var isTouching = false
  @State private var hasReachedLimit = false

  /// How far the conversation has to be pulled to start the new chat.
  private let limit: CGFloat = 72

  private var progress: CGFloat {
    Self.progress(for: pull, limit: limit)
  }

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
      } action: { _, distance in
        let next = Self.clamped(distance)
        if pull != next { pull = next }
        if distance >= limit {
          // One new chat per pull; the pull has to fall back before another.
          guard isTouching, !hasReachedLimit else { return }
          hasReachedLimit = true
          InteractionFeedback.shared.send(.selection)
          onNewChat()
        } else if distance < limit / 2 {
          hasReachedLimit = false
        }
      }
      .onScrollPhaseChange { _, phase in
        isTouching = phase == .tracking || phase == .interacting
        guard !isTouching else { return }
        hasReachedLimit = false
        if pull != 0 { pull = 0 }
      }
      .overlay(alignment: .top) {
        if isTouching && pull > 0 {
          ProgressView()
            .controlSize(.small)
            .tint(MemoraPalette.textSecondary)
            .opacity(Double(progress))
            .scaleEffect(0.7 + 0.3 * progress)
            .offset(y: min(pull / 2, MemoraSpacing.xxl))
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
  }

  /// Keeps a runaway rubber-band value from drawing a spinner far down the
  /// conversation.
  private static func clamped(_ pull: CGFloat) -> CGFloat {
    min(pull, 160)
  }

  private static func progress(for pull: CGFloat, limit: CGFloat) -> CGFloat {
    min(1, max(0, pull) / limit)
  }
}
