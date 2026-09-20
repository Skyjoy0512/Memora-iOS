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

/// Hides a screen's own top controls (section switch, filters) while the content
/// is scrolled down, so the list gets the full height.
private struct LibraryChromeScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { previousOffset, offset in
        if offset <= 24 {
          model.isLibraryChromeHidden = false
        } else if offset > previousOffset + 4 {
          model.isLibraryChromeHidden = true
        } else if offset < previousOffset - 4 {
          model.isLibraryChromeHidden = false
        }
      }
      .onDisappear {
        model.isLibraryChromeHidden = false
      }
  }
}

extension View {
  func hideBottomBarOnScroll() -> some View {
    modifier(BottomBarScrollBehavior())
  }

  func hideTopChromeOnScroll() -> some View {
    modifier(LibraryChromeScrollBehavior())
  }
}
