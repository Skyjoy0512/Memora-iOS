import Foundation

/// Long-draft disclosure follows chatgpt-ios-ui's 180-character threshold.
/// The native field stays mounted; height limits leave room for the keyboard and controls.
enum AIComposerLayoutPolicy {
  static func offersExpansion(for text: String) -> Bool {
    let prefix = text.prefix(181)
    return prefix.count > 180 || prefix.filter { $0.isNewline }.count >= 3
  }

  static func lines(isExpanded: Bool, isTall: Bool, lineHeight: CGFloat = 24) -> ClosedRange<Int> {
    guard isExpanded else { return 1...1 }
    let height = maximumTextHeight(isExpanded: true, isTall: isTall) ?? 160
    let safeLineHeight = lineHeight.isFinite && lineHeight > 0 ? lineHeight : 24
    let count = max(1, min(CGFloat(isTall ? 12 : 6), floor(height / safeLineHeight)))
    return 1...Int(count)
  }

  static func maximumTextHeight(isExpanded: Bool, isTall: Bool) -> CGFloat? {
    isExpanded ? (isTall ? 280 : 160) : nil
  }
}
