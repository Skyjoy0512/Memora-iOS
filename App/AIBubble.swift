import SwiftUI

/// The person's message bubble, on a quiet neutral surface on the right. Memora's
/// replies have no bubble; they read as text on the page.
struct AIBubble: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.vertical, MemoraSpacing.md)
      .foregroundStyle(MemoraPalette.textPrimary)
      .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: MemoraRadius.bubble, style: .continuous))
  }
}

extension View {
  func aiBubble() -> some View {
    modifier(AIBubble())
  }
}
