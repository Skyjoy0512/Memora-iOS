/// Arrival ranges never move, so a new token cannot dim an earlier fading one.
/// Older text always draws in full, even when a network burst exceeds the budget.
struct StreamingTextTail {
  private(set) var characterCount = 0
  private(set) var ranges: [Range<Int>] = []

  var start: Int { ranges.first?.lowerBound ?? characterCount }

  func updating(to count: Int) -> Self {
    guard count >= characterCount else { return Self(characterCount: count) }
    guard count > characterCount else { return self }
    var next = self
    // Split only the bounded new suffix, never the entire answer.
    let firstNew = max(characterCount, count - 64)
    next.ranges += stride(from: firstNew, to: count, by: 8).map {
      $0..<min(count, $0 + 8)
    }
    next.ranges = Array(next.ranges.filter { count - $0.lowerBound <= 64 }.suffix(8))
    next.characterCount = count
    return next
  }

  static func opacity(visibleCharacters: Double, range: Range<Int>) -> Double {
    guard !range.isEmpty else { return 1 }
    let fraction = min(1, max(0, (visibleCharacters - Double(range.lowerBound)) / Double(range.count)))
    return fraction * fraction * (3 - 2 * fraction)
  }
}
