import Foundation

enum SpeakerTranscriptAligner {
  static func align(_ transcript: [TranscriptSegment], intervals: [SpeakerInterval], minimumDuration: TimeInterval) -> [TranscriptSegment] {
    let valid = intervals.filter(\.isValid).sorted { $0.start < $1.start }
    return transcript.map { original in
      guard original.identificationStatus != .manual else { return original }
      var segment = original
      segment.speakerID = nil
      segment.speakerIsCertain = false
      segment.speaker = "話者不明"
      guard original.timestamp.isFinite, original.timestamp >= 0,
            let end = original.endTime, end.isFinite, end > original.timestamp else {
        segment.identificationStatus = .insufficientTiming
        return segment
      }
      let overlapping = valid.filter { $0.start < end && $0.end > original.timestamp }
      let ids = Set(overlapping.map(\.speakerID))
      guard ids.count == 1, let id = ids.first else {
        let hasOverlap = overlapping.contains { interval in
          overlapping.contains { other in
            other.speakerID != interval.speakerID && max(other.start, interval.start) < min(other.end, interval.end)
          }
        }
        segment.identificationStatus = hasOverlap ? .overlap : .unassigned
        segment.speaker = hasOverlap ? "未確定（発話の重なり）" : "話者不明"
        return segment
      }
      var coveredEnd = original.timestamp
      var coveredDuration = 0.0
      for interval in overlapping {
        coveredDuration += max(0, min(end, interval.end) - max(coveredEnd, interval.start))
        coveredEnd = max(coveredEnd, interval.end)
      }
      guard end - original.timestamp >= minimumDuration,
            coveredDuration >= end - original.timestamp - 0.001 else {
        segment.identificationStatus = .unassigned
        return segment
      }
      segment.speakerID = id
      segment.speaker = "話者\(id)"
      segment.identificationStatus = .anonymous
      return segment
    }
  }
}
