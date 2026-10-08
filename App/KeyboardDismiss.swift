import SwiftUI
import UIKit

extension View {
  /// Puts the keyboard away when a tap lands anywhere other than the field being
  /// edited, the way the system does. Taps still reach the control underneath.
  func dismissKeyboardOnOutsideTap() -> some View {
    background(KeyboardDismissInstaller().allowsHitTesting(false))
  }
}

/// Installs one tap recognizer on the window. A window-level recognizer sees
/// every tap, so it keeps working inside sheets and popovers too.
private struct KeyboardDismissInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    InstallerView()
  }

  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class InstallerView: UIView, UIGestureRecognizerDelegate {
    private var hasInstalled = false

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let window, !hasInstalled else { return }
      hasInstalled = true

      let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
      tap.cancelsTouchesInView = false
      // Never hold up the touches that reach controls underneath, or the first
      // tap on a segmented control or button can be missed.
      tap.delaysTouchesBegan = false
      tap.delaysTouchesEnded = false
      tap.delegate = self
      window.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
      window?.endEditing(true)
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldReceive touch: UITouch
    ) -> Bool {
      // Keep the keyboard while the person taps the field they are editing;
      // every other tap — buttons, cards, empty space — dismisses it.
      !(touch.view?.isInsideTextInput ?? false)
    }
  }
}

private extension UIView {
  var isInsideTextInput: Bool {
    var node: UIView? = self
    while let current = node {
      if current is UITextInput || current is MarkdownEditingToolbar { return true }
      node = current.superview
    }
    return false
  }
}
