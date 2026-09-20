import SwiftUI

private struct BottomBarScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { previousOffset, offset in
        // Back at the top always brings the bar home; otherwise the direction of
        // the scroll decides, so scrolling up recovers it before reaching the top.
        if offset <= 24 {
          model.isBottomBarHidden = false
        } else if offset > previousOffset + 4 {
          model.isBottomBarHidden = true
        } else if offset < previousOffset - 4 {
          model.isBottomBarHidden = false
        }
      }
      .onDisappear {
        model.isBottomBarHidden = false
      }
  }
}

extension View {
  func hideBottomBarOnScroll() -> some View {
    modifier(BottomBarScrollBehavior())
  }
}
