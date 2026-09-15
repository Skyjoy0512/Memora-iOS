import SwiftUI

private struct BottomBarScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top > 24
      } action: { _, isAwayFromTop in
        model.isBottomBarHidden = isAwayFromTop
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
