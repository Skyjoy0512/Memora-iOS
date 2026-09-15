import SwiftUI

private struct BottomBarScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model
  @State private var lastOffset: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { oldOffset, newOffset in
        let delta = newOffset - oldOffset
        if newOffset < 12 {
          model.isBottomBarCompact = false
        } else if delta > 5, newOffset > lastOffset {
          model.isBottomBarCompact = true
        } else if delta < -5, newOffset < lastOffset {
          model.isBottomBarCompact = false
        }
        lastOffset = newOffset
      }
      .onDisappear {
        model.isBottomBarCompact = false
      }
  }
}

extension View {
  func compactBottomBarOnScroll() -> some View {
    modifier(BottomBarScrollBehavior())
  }
}
