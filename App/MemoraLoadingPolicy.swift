import Foundation

enum MemoraLoadingPolicy {
  static let skeletonDelay: Duration = .milliseconds(180)
  static let explanationDelay: Duration = .seconds(2)
  static let actionsDelay: Duration = .seconds(5)
  static let shimmerSeconds = 1.6

  static func stage(after elapsed: Duration) -> Int {
    if elapsed >= actionsDelay { return 3 }
    if elapsed >= explanationDelay { return 2 }
    if elapsed >= skeletonDelay { return 1 }
    return 0
  }
}
