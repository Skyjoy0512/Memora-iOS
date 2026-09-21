import SwiftUI

private struct BottomBarScrollBehavior: ViewModifier {
  @Environment(MemoraModel.self) private var model
  /// Which screen this scroll view belongs to, so it can only speak for itself.
  var screenID: String

  func body(content: Content) -> some View {
    content
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { previousOffset, offset in
        setHidden(shouldHide(previousOffset: previousOffset, offset: offset))
      }
      .onAppear {
        // Hidden controls are hard to find with VoiceOver, so they stay put.
        if UIAccessibility.isVoiceOverRunning {
          setHidden(false)
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
        if UIAccessibility.isVoiceOverRunning {
          setHidden(false)
        }
      }
      .onDisappear {
        setHidden(false)
      }
  }

  /// Back at the top always brings the bar home; otherwise the direction of the
  /// scroll decides, so scrolling up recovers it before reaching the top. The
  /// small threshold keeps a layout change from flipping the bar back and forth.
  private func shouldHide(previousOffset: CGFloat, offset: CGFloat) -> Bool {
    if offset <= 24 {
      return false
    }
    if offset > previousOffset + 4 {
      return true
    }
    if offset < previousOffset - 4 {
      return false
    }
    return model.isBottomBarHidden(for: screenID)
  }

  private func setHidden(_ hidden: Bool) {
    guard !UIAccessibility.isVoiceOverRunning else {
      model.setBottomBarHidden(false, for: screenID)
      return
    }
    guard model.isBottomBarHidden(for: screenID) != hidden else { return }
    model.setBottomBarHidden(hidden, for: screenID)
  }
}

extension View {
  /// `screenID` names the screen so only the screen being read can hide the bar.
  func hideBottomBarOnScroll(_ screenID: String) -> some View {
    modifier(BottomBarScrollBehavior(screenID: screenID))
  }
}
