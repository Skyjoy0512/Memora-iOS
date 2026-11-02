import Foundation

/// Candidate windows for evaluation only. The shipping recognizer retains the
/// whole chunk until quiet Japanese speech has passed the acceptance corpus.
struct VoiceActivityTimeline: Sendable {
  var ranges: [SourceMediaChunk]

  static func candidates(probabilities: [Float], frameDuration: TimeInterval,
                         duration: TimeInterval) throws -> Self {
    guard duration.isFinite, duration > 0, duration <= SourceMediaChunk.durationPerChunk + 1,
          frameDuration.isFinite, frameDuration > 0 else { throw SourceMediaFailure.invalidDuration }
    let whole = Self(ranges: [.init(start: 0, duration: duration)])
    guard !probabilities.isEmpty, probabilities.count <= 100_000,
          probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
          Double(probabilities.count) * frameDuration >= duration - frameDuration else { return whole }
    var kept: [SourceMediaChunk] = []
    // Even low probability and isolated acknowledgements survive. Padding and
    // merging retain context; no minimum speech length filters out a short word.
    for (index, probability) in probabilities.enumerated() where probability > 0.01 {
      let start = max(0, Double(index) * frameDuration - 0.75)
      let end = min(duration, Double(index + 1) * frameDuration + 0.75)
      guard end > start else { continue }
      if let last = kept.last, start <= last.start + last.duration + 2 {
        kept[kept.count - 1].duration = max(last.start + last.duration, end) - last.start
      } else {
        kept.append(.init(start: start, duration: end - start))
      }
    }
    return kept.isEmpty ? whole : Self(ranges: kept)
  }

  /// Maps a proposed concatenation back to the unchanged original. A boundary
  /// belongs to the following window, so a skipped gap never shifts a citation.
  func originalTime(for processedTime: TimeInterval) -> TimeInterval? {
    guard processedTime.isFinite, processedTime >= 0 else { return nil }
    var cursor: TimeInterval = 0
    for range in ranges {
      if processedTime < cursor + range.duration { return range.start + processedTime - cursor }
      cursor += range.duration
    }
    if processedTime == cursor, let last = ranges.last { return last.start + last.duration }
    return nil
  }
}
