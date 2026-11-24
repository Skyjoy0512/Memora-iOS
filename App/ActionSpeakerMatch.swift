import Foundation

/// Finds the transcript segment that most likely states one summary action.
/// A summary rewrites what was said, so only a clear and unique wording overlap
/// is accepted; anything weaker leaves the action unattributed rather than
/// guessing a speaker.
enum ActionSpeakerMatch {
  static let minimumCharacters = 6
  static let minimumScore = 0.45
  static let minimumMargin = 0.12

  static func speakerID(forAction title: String, in transcript: [TranscriptSegment]) -> String? {
    let target = normalized(title)
    guard target.count >= minimumCharacters else { return nil }
    var bestBySpeaker: [String: Double] = [:]
    for segment in transcript {
      guard let speakerID = segment.speakerID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !speakerID.isEmpty else { continue }
      let score = similarity(target, normalized(segment.text))
      bestBySpeaker[speakerID] = max(bestBySpeaker[speakerID] ?? 0, score)
    }
    let ranked = bestBySpeaker.sorted { $0.value > $1.value }
    guard let best = ranked.first, best.value >= minimumScore else { return nil }
    if ranked.count > 1, best.value - ranked[1].value < minimumMargin { return nil }
    return best.key
  }

  /// Wording-only overlap of two normalized strings, measured as the Dice
  /// coefficient of their character bigrams. Character pairs survive Japanese
  /// rewriting better than whole words, which have no separator to split on.
  static func similarity(_ left: String, _ right: String) -> Double {
    let leftBigrams = bigrams(left)
    let rightBigrams = bigrams(right)
    guard !leftBigrams.isEmpty, !rightBigrams.isEmpty else { return 0 }
    var remaining: [String: Int] = [:]
    for bigram in leftBigrams { remaining[bigram, default: 0] += 1 }
    var overlap = 0
    for bigram in rightBigrams {
      guard let count = remaining[bigram], count > 0 else { continue }
      overlap += 1
      remaining[bigram] = count - 1
    }
    return Double(2 * overlap) / Double(leftBigrams.count + rightBigrams.count)
  }

  private static func bigrams(_ text: String) -> [String] {
    let characters = Array(text)
    guard characters.count > 1 else { return [] }
    return (0..<characters.count - 1).map { String(characters[$0...$0 + 1]) }
  }

  /// Keeps only letters and digits, so spacing, punctuation and quote marks do
  /// not decide whether two sentences look alike.
  private static func normalized(_ text: String) -> String {
    let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    let kept = CharacterSet.letters.union(.decimalDigits)
    return String(folded.unicodeScalars.filter { kept.contains($0) }.map(Character.init))
  }
}
