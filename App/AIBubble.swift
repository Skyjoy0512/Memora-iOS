import SwiftUI

/// The person's message bubble, on a quiet neutral surface on the right. Memora's
/// replies have no bubble; they read as text on the page.
struct AIBubble: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .foregroundStyle(MemoraPalette.textPrimary)
      .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

extension View {
  func aiBubble() -> some View {
    modifier(AIBubble())
  }
}
