import Foundation

/// A settled prefix, including silent chunks. It is never published as a
/// source's readable transcript until all chunks have finished.
struct SourceMediaCheckpoint: Codable {
  var duration: TimeInterval
  var completedChunks: Int
  var blocks: [ProjectSourceText]
  var segments: [TranscriptSegment]? = nil
  var chunkRevisions: [SourceMediaChunkRevision]? = nil

  init(duration: TimeInterval, completedChunks: Int, blocks: [ProjectSourceText],
       segments: [TranscriptSegment]? = nil, chunkRevisions: [SourceMediaChunkRevision]? = nil) {
    self.duration = duration
    self.completedChunks = completedChunks
    self.blocks = blocks
    self.segments = segments
    self.chunkRevisions = chunkRevisions
  }

  private enum CodingKeys: String, CodingKey {
    case duration, completedChunks, blocks, segments, chunkRevisions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    completedChunks = try container.decode(Int.self, forKey: .completedChunks)
    blocks = try container.decode([ProjectSourceText].self, forKey: .blocks)
    segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments)
    // Optional provenance may be discarded without losing a valid transcript.
    chunkRevisions = try? container.decodeIfPresent([SourceMediaChunkRevision].self, forKey: .chunkRevisions)
  }

  mutating func recordSettledChunk(index: Int, segmentRange: Range<Int> = 0..<0,
                                   blockRange: Range<Int> = 0..<0, key: String) {
    guard let revision = SourceMediaChunkRevision.make(checkpoint: self, key: key, index: index,
      segmentRange: segmentRange, blockRange: blockRange) else { return }
    var revisions = chunkRevisions ?? []
    revisions.removeAll { $0.chunkIndex == index }
    revisions.append(revision)
    chunkRevisions = revisions.sorted { $0.chunkIndex < $1.chunkIndex }
  }

  func validatedChunkRevisions(key: String) -> [SourceMediaChunkRevision]? {
    guard let revisions = chunkRevisions, !revisions.isEmpty,
          revisions.count <= completedChunks,
          let chunks = try? SourceMediaChunk.plan(duration: duration), revisions.count <= chunks.count else { return nil }
    var index = -1, segmentEnd = 0, blockEnd = 0
    var valid: [SourceMediaChunkRevision] = []
    for revision in revisions {
      guard revision.chunkIndex > index, let ranges = revision.ranges(in: self),
            ranges.segments.lowerBound >= segmentEnd, ranges.blocks.lowerBound >= blockEnd else { return nil }
      index = revision.chunkIndex
      segmentEnd = ranges.segments.upperBound
      blockEnd = ranges.blocks.upperBound
      if revision.matches(checkpoint: self, key: key) { valid.append(revision) }
    }
    return valid.isEmpty ? nil : valid
  }

  var hasText: Bool { !blocks.isEmpty || !(segments?.isEmpty ?? true) }

  func persistenceData(maximumBytes: Int) throws -> Data? {
    guard maximumBytes > 0 else { return nil }
    let encoder = JSONEncoder()
    let data = try encoder.encode(self)
    if data.count <= maximumBytes { return data }
    guard chunkRevisions != nil else { return nil }
    // Optional provenance must not evict a transcript that fit the old codec.
    var withoutRevisions = self
    withoutRevisions.chunkRevisions = nil
    let fallback = try encoder.encode(withoutRevisions)
    return fallback.count <= maximumBytes ? fallback : nil
  }

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
