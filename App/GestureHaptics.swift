import SwiftUI
import UIKit

/// One small haptic for the two gestures that go everywhere: a discrete tap on
/// any control, and a horizontal swipe (a list row's actions, the side menu, a
/// paged strip). Installed on the window, so a tap or swipe in a sheet or on
/// the tab bar is felt too. The recognizers never cancel touches, so the
/// control under the finger still handles the gesture as before; keyboard keys
/// are left to their own clicks.
struct GestureHapticsInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = HostView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class HostView: UIView, UIGestureRecognizerDelegate {
    private var didFireSwipe = false

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let window, !window.hasGestureHaptics else { return }

      let tap = HapticTapRecognizer(target: self, action: #selector(handleTap))
      tap.cancelsTouchesInView = false
      tap.delegate = self
      window.addGestureRecognizer(tap)

      let pan = HapticSwipeRecognizer(target: self, action: #selector(handleSwipe))
      pan.cancelsTouchesInView = false
      pan.delegate = self
      window.addGestureRecognizer(pan)
    }

    @objc private func handleTap() {
      Haptics.tap()
    }

    /// A bump as a horizontal swipe passes the point where it would reveal a
    /// row's actions, once per gesture.
    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
      switch gesture.state {
      case .began:
        didFireSwipe = false
      case .changed:
        guard !didFireSwipe else { return }
        let translation = gesture.translation(in: gesture.view)
        if abs(translation.x) > 44, abs(translation.x) > abs(translation.y) * 1.5 {
          didFireSwipe = true
          Haptics.swipe()
        }
      default:
        didFireSwipe = false
      }
    }

    /// A gesture inside the keyboard is the keyboard's own; the key already
    /// clicks. A slider is a drag with its own feel, not a swipe to act on.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      var view = touch.view
      while let current = view {
        if current is UIInputView { return false }
        if current is UISlider { return false }
        if NSStringFromClass(type(of: current)).localizedCaseInsensitiveContains("keyboard") {
          return false
        }
        view = current.superview
      }
      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

/// The app's haptics, kept in one place so a gesture feels the same everywhere.
@MainActor
enum Haptics {
  /// A discrete tap on a control.
  static func tap() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred(intensity: 0.7)
  }

  /// A horizontal swipe crossing the point where it would act.
  static func swipe() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred(intensity: 0.5)
  }

  /// A finished answer or a completed change.
  static func success() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
}

private extension UIWindow {
  var hasGestureHaptics: Bool {
    gestureRecognizers?.contains { $0 is HapticTapRecognizer || $0 is HapticSwipeRecognizer } ?? false
  }
}

private final class HapticTapRecognizer: UITapGestureRecognizer {}

private final class HapticSwipeRecognizer: UIPanGestureRecognizer {}
