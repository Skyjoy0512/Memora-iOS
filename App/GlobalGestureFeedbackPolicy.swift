import Foundation

/// One signal for an intentional horizontal swipe; scrolling and invalid samples stay silent.
enum GlobalGestureFeedbackPolicy {
  static func shouldSignalSwipe(x: CGFloat, y: CGFloat, hasSignalled: Bool) -> Bool {
    !hasSignalled && x.isFinite && y.isFinite && abs(x) > 44 && abs(x) > abs(y) * 1.5
  }
}
