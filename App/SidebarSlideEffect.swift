import SwiftUI

struct SidebarSlideEffect: GeometryEffect {
  var offset: CGFloat

  var animatableData: CGFloat {
    get { offset }
    set { offset = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
  }
}
