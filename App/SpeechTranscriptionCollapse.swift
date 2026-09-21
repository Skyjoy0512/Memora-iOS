import Foundation

/// One update from a speech transcriber. A progressive engine reports the same
/// phrase again and again as it grows, so an update is progress, not a phrase.
struct SpeechUpdate: Equatable {
  var text: String
  var timestamp: TimeInterval
  var isFinal: Bool
}

/// Collapses a transcriber's updates into one segment per spoken phrase.
///
/// Without this, every progressive step becomes its own line —「こ」「こん」
/// 「こんに」… — and the transcript holds the same sentence once per character.
enum SpeechTranscriptionCollapse {
  static func collapse(_ updates: [SpeechUpdate]) -> [TranscriptSegment] {
    var finalized: [TranscriptSegment] = []
    var finalizedKeys: Set<Int> = []
    var progress: [Int: TranscriptSegment] = [:]

    for update in updates {
      let key = key(for: update.timestamp)
      let segment = TranscriptSegment(
        id: UUID(),
        speaker: "話者",
        speakerIsCertain: false,
        timestamp: update.timestamp,
        text: update.text
      )
      if update.isFinal {
        finalizedKeys.insert(key)
        // A phrase's start time can move by a step between its updates, so the
        // neighbouring buckets are cleared with it.
        for offset in -1...1 {
          progress.removeValue(forKey: key + offset)
        }
        finalized.append(segment)
      } else {
        // Only the newest progress for that phrase is kept, so a phrase that is
        // still being recognized does not leave its earlier steps behind.
        progress[key] = segment
      }
    }

    // Progress whose phrase never finalized (a recording cut off mid-sentence)
    // is kept as its latest text, so nothing spoken is lost.
    let finalizedNeighbourhood = Set(finalizedKeys.flatMap { [$0 - 1, $0, $0 + 1] })
    let unfinished = progress.filter { !finalizedNeighbourhood.contains($0.key) }.values
    return (finalized + unfinished).sorted { $0.timestamp < $1.timestamp }
  }

  /// Collapses a transcript that was already stored one progress step at a time,
  /// so a record written by the earlier build reads as sentences again. Returns
  /// nil when nothing needs changing, leaving a healthy record untouched.
  static func repair(_ segments: [TranscriptSegment]) -> [TranscriptSegment]? {
    guard segments.count > 1 else { return nil }

    var repaired: [TranscriptSegment] = []
    var changed = false
    var index = 0

    while index < segments.count {
      let groupKey = key(for: segments[index].timestamp)
      var group = [segments[index]]
      var next = index + 1
      // One step of a phrase can carry a start time a bucket off from the
      // others, so the neighbouring buckets join the same group.
      while next < segments.count, abs(key(for: segments[next].timestamp) - groupKey) <= 1 {
        group.append(segments[next])
        next += 1
      }

      // Steps of the same phrase are each a prefix of the next. Real sentences
      // sharing a start time are not shaped that way, so nothing else collapses.
      if group.count > 1, isPrefixRun(group.map(\.text)) {
        repaired.append(group[group.count - 1])
        changed = true
      } else {
        repaired.append(contentsOf: group)
      }
      index = next
    }

    return changed ? repaired : nil
  }

  /// True when each text is a prefix of the one after it.
  private static func isPrefixRun(_ texts: [String]) -> Bool {
    guard texts.count > 1, texts.last?.isEmpty == false else { return false }
    for index in 0..<(texts.count - 1) where !texts[index + 1].hasPrefix(texts[index]) {
      return false
    }
    return true
  }

  /// Phrases are matched by their start time, rounded to a tenth of a second so
  /// small differences between updates do not split one phrase in two.
  private static func key(for timestamp: TimeInterval) -> Int {
    Int((timestamp * 10).rounded())
  }
}
