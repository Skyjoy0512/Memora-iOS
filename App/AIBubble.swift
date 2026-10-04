import SwiftUI

/// A message bubble: Memora's in grey on the left, the person's in the accent
/// colour on the right.
struct AIBubble: ViewModifier {
  var isFromPerson = false

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .foregroundStyle(isFromPerson ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .background(
        isFromPerson ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
      )
  }
}

extension View {
  func aiBubble(isFromPerson: Bool = false) -> some View {
    modifier(AIBubble(isFromPerson: isFromPerson))
  }
}
