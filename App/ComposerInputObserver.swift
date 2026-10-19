import SwiftUI
import UIKit

/// Observes the existing native field; it never installs a delegate or changes its text.
struct ComposerInputObserver: UIViewRepresentable {
  var state: ComposerInputState
  var isActive: Bool

  func makeCoordinator() -> Coordinator { Coordinator(state: state) }
  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    context.coordinator.anchor = view
    return view
  }
  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.state = state
    context.coordinator.setActive(isActive)
  }
  static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.stop() }

  @MainActor
  final class Coordinator {
    var state: ComposerInputState
    weak var anchor: UIView?
    var timer: Timer?
    init(state: ComposerInputState) { self.state = state }
    func setActive(_ active: Bool) {
      if !active {
        stop()
        DispatchQueue.main.async { [weak self] in
          guard let self, self.timer == nil else { return }
          if self.state.value != nil { self.state.value = nil }
        }
        return
      }
      guard timer == nil else { return }
      // Selection-only movement and IME marking do not always change the SwiftUI binding.
      let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() {
      if state.inputView?.isFirstResponder != true {
        var ancestor = anchor?.superview
        var input: UIView?
        // A presented settings field belongs to another host, even in the same window.
        while let current = ancestor, !(current is UIWindow) {
          if let found = findInput(current) { input = found; break }
          ancestor = current.superview
        }
        state.inputView = input
      }
      let snapshot = state.snapshot()
      if state.value != snapshot { state.value = snapshot }
    }
    private func findInput(_ view: UIView) -> UIView? {
      if view.isFirstResponder, view is any UITextInput,
         let anchor, let window = anchor.window, view.window === window,
         view.convert(view.bounds, to: window).insetBy(dx: -2, dy: -2)
           .intersects(anchor.convert(anchor.bounds, to: window).insetBy(dx: -2, dy: -2)),
         (view as? UITextField)?.isSecureTextEntry != true, (view as? UITextView)?.isSecureTextEntry != true {
        return view
      }
      for child in view.subviews {
        if let found = findInput(child) { return found }
      }
      return nil
    }
  }
}
