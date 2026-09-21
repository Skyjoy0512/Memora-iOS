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

  /// Phrases are matched by their start time, rounded to a tenth of a second so
  /// small differences between updates do not split one phrase in two.
  private static func key(for timestamp: TimeInterval) -> Int {
    Int((timestamp * 10).rounded())
  }
}
