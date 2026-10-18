import SwiftUI
import UIKit

/// Preserves the legacy branch's global tap/swipe feedback through the current,
/// recording-aware preference and debounce gates. It never consumes a control's touches.
struct GestureHapticsInstaller: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = HostView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class HostView: UIView, UIGestureRecognizerDelegate {
    private var didSignalSwipe = false

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let window, window.gestureRecognizers?.contains(where: {
        $0 is FeedbackTapRecognizer || $0 is FeedbackSwipeRecognizer
      }) != true else { return }
      let tap = FeedbackTapRecognizer(target: self, action: #selector(tapped))
      tap.cancelsTouchesInView = false
      tap.delegate = self
      window.addGestureRecognizer(tap)
      let swipe = FeedbackSwipeRecognizer(target: self, action: #selector(swiped))
      swipe.cancelsTouchesInView = false
      swipe.delegate = self
      window.addGestureRecognizer(swipe)
    }

    @objc private func tapped() {
      InteractionFeedback.shared.send(.tap)
    }

    @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
      switch gesture.state {
      case .began: didSignalSwipe = false
      case .changed:
        let translation = gesture.translation(in: gesture.view)
        if GlobalGestureFeedbackPolicy.shouldSignalSwipe(x: translation.x, y: translation.y, hasSignalled: didSignalSwipe) {
          didSignalSwipe = true
          InteractionFeedback.shared.send(.selection)
        }
      default: didSignalSwipe = false
      }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      var ancestor = touch.view
      while let view = ancestor {
        if view is UIInputView || view is UITextField || view is UITextView || view is UISlider { return false }
        if NSStringFromClass(type(of: view)).localizedCaseInsensitiveContains("keyboard") { return false }
        ancestor = view.superview
      }
      return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
  }
}

private final class FeedbackTapRecognizer: UITapGestureRecognizer {}
private final class FeedbackSwipeRecognizer: UIPanGestureRecognizer {}
