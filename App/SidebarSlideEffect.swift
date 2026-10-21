import SwiftUI

struct SidebarSlideEffect: GeometryEffect {
  var offset: CGFloat
  var onClosed: () -> Void = {}

  var animatableData: CGFloat {
    get { offset }
    set {
      offset = newValue
      if newValue == 0 {
        // Leave the render pass before mutating presentation state.
        let completed = onClosed
        Task { @MainActor in completed() }
      }
    }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
  }
}
