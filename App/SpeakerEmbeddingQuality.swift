import Foundation

enum SpeakerEmbeddingQuality {
  static func duration(_ intervals: [SpeakerInterval]) -> TimeInterval {
    var end = 0.0
    var total = 0.0
    for interval in intervals.filter(\.isValid).sorted(by: { $0.start < $1.start }) {
      total += max(0, interval.end - max(end, interval.start))
      end = max(end, interval.end)
    }
    return total
  }

  static func eligible(speakerID: String, start: TimeInterval, end: TimeInterval,
                       intervals: [SpeakerInterval], minimumSpeechDuration: TimeInterval) -> Bool {
    guard start.isFinite, end.isFinite, start >= 0, end > start,
          minimumSpeechDuration.isFinite, minimumSpeechDuration > 0 else { return false }
    let own = intervals.filter { $0.isValid && $0.speakerID == speakerID && $0.end > start && $0.start < end }
      .map { SpeakerInterval(speakerID: speakerID, start: max(start, $0.start), end: min(end, $0.end)) }
    guard duration(own) >= minimumSpeechDuration else { return false }
    return !intervals.contains { other in
      other.isValid && other.speakerID != speakerID
        && own.contains { max($0.start, other.start) < min($0.end, other.end) }
    }
  }
}
