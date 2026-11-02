import Foundation

/// A settled prefix, including silent chunks. It is never published as a
/// source's readable transcript until all chunks have finished.
struct SourceMediaCheckpoint: Codable {
  var duration: TimeInterval
  var completedChunks: Int
  var blocks: [ProjectSourceText]
  var segments: [TranscriptSegment]? = nil

  var hasText: Bool { !blocks.isEmpty || !(segments?.isEmpty ?? true) }

  func isValid(for duration: TimeInterval) -> Bool {
    guard self.duration == duration, let chunks = try? SourceMediaChunk.plan(duration: duration),
          completedChunks > 0, completedChunks <= chunks.count else { return false }
    let last = chunks[completedChunks - 1]
    let end = last.start + last.duration
    var previous: TimeInterval = 0
    for block in blocks {
      guard block.page == nil, let time = block.time, time.isFinite, time >= previous, time <= end,
            !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
      previous = time
    }
    previous = 0
    for segment in segments ?? [] {
      guard segment.timestamp.isFinite, segment.timestamp >= previous, segment.timestamp <= end,
            !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            segment.endTime.map({ $0.isFinite && $0 >= segment.timestamp && $0 <= end + 1 }) ?? true else { return false }
      previous = segment.timestamp
    }
    return true
  }
}
