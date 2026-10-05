import SwiftUI
import UIKit

/// One light tap haptic for a discrete tap anywhere in the app, so every
/// control answers with the same small bump — including a tap in a sheet or on
/// the tab bar, which a SwiftUI gesture on the content would miss. It is
/// installed on the window and never cancels touches, so the control under the
/// finger still handles the tap as before; keyboard keys are left to their own
/// clicks.
struct TapHapticsInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = HostView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class HostView: UIView, UIGestureRecognizerDelegate {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let window, !window.hasHapticTapRecognizer else { return }
      let tap = HapticTapRecognizer(target: self, action: #selector(fire))
      tap.cancelsTouchesInView = false
      tap.delegate = self
      window.addGestureRecognizer(tap)
    }

    @objc private func fire() {
      Haptics.tap()
    }

    /// A tap inside the keyboard is the keyboard's own; the key already clicks.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      var view = touch.view
      while let current = view {
        if current is UIInputView { return false }
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

/// The app's haptics, kept in one place so a tap feels the same everywhere.
@MainActor
enum Haptics {
  /// A discrete tap on a control.
  static func tap() {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred(intensity: 0.7)
  }

  /// A finished answer or a completed change.
  static func success() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
}

private extension UIWindow {
  var hasHapticTapRecognizer: Bool {
    gestureRecognizers?.contains { $0 is HapticTapRecognizer } ?? false
  }
}

private final class HapticTapRecognizer: UITapGestureRecognizer {}
