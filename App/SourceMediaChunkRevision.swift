import CryptoKit
import Foundation

/// Identifies a settled interval without replacing its original segment IDs.
/// Its version covers source/configuration and every stored speaker/text field.
struct SourceMediaChunkRevision: Codable, Equatable, Sendable {
  var schemaVersion = 1
  var id: String
  var sourceBinding: String
  var chunkIndex: Int
  var segmentOffset: Int
  var segmentCount: Int
  var blockOffset: Int
  var blockCount: Int
  var contentFingerprint: String

  static func make(checkpoint: SourceMediaCheckpoint, key: String, index: Int,
                   segmentRange: Range<Int>, blockRange: Range<Int>) -> Self? {
    guard !key.isEmpty, segmentRange.lowerBound >= 0,
          segmentRange.upperBound <= (checkpoint.segments?.count ?? 0), blockRange.lowerBound >= 0,
          blockRange.upperBound <= checkpoint.blocks.count,
          let chunks = try? SourceMediaChunk.plan(duration: checkpoint.duration),
          index >= 0, index < checkpoint.completedChunks, index < chunks.count else { return nil }
    let binding = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    let chunk = chunks[index]
    guard hasValidTimes(checkpoint: checkpoint, segments: segmentRange, blocks: blockRange, chunk: chunk),
          let id = hash(Identity(sourceBinding: binding, index: index, start: chunk.start, duration: chunk.duration)),
          let fingerprint = fingerprint(id: id, checkpoint: checkpoint, segments: segmentRange, blocks: blockRange) else { return nil }
    return Self(id: id, sourceBinding: binding, chunkIndex: index,
      segmentOffset: segmentRange.lowerBound, segmentCount: segmentRange.count,
      blockOffset: blockRange.lowerBound, blockCount: blockRange.count, contentFingerprint: fingerprint)
  }

  func ranges(in checkpoint: SourceMediaCheckpoint) -> (segments: Range<Int>, blocks: Range<Int>)? {
    let count = checkpoint.segments?.count ?? 0
    guard segmentOffset >= 0, segmentOffset <= count, segmentCount >= 0, segmentCount <= count - segmentOffset,
          blockOffset >= 0, blockOffset <= checkpoint.blocks.count,
          blockCount >= 0, blockCount <= checkpoint.blocks.count - blockOffset else { return nil }
    return (segmentOffset..<(segmentOffset + segmentCount), blockOffset..<(blockOffset + blockCount))
  }

  func matches(checkpoint: SourceMediaCheckpoint, key: String) -> Bool {
    guard schemaVersion == 1, id.utf8.count == 64, sourceBinding.utf8.count == 64, contentFingerprint.utf8.count == 64,
          !key.isEmpty, let ranges = ranges(in: checkpoint), chunkIndex >= 0, chunkIndex < checkpoint.completedChunks,
          let chunks = try? SourceMediaChunk.plan(duration: checkpoint.duration), chunkIndex < chunks.count else { return false }
    let binding = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    let chunk = chunks[chunkIndex]
    guard binding == sourceBinding,
          Self.hash(Identity(sourceBinding: binding, index: chunkIndex, start: chunk.start, duration: chunk.duration)) == id,
          Self.hasValidTimes(checkpoint: checkpoint, segments: ranges.segments, blocks: ranges.blocks, chunk: chunk) else { return false }
    return Self.fingerprint(id: id, checkpoint: checkpoint, segments: ranges.segments, blocks: ranges.blocks) == contentFingerprint
  }

  private static func hasValidTimes(checkpoint: SourceMediaCheckpoint, segments: Range<Int>,
                                    blocks: Range<Int>, chunk: SourceMediaChunk) -> Bool {
    let end = chunk.start + chunk.duration
    for segment in (checkpoint.segments ?? [])[segments] {
      guard segment.timestamp.isFinite, segment.timestamp >= chunk.start, segment.timestamp <= end,
            segment.endTime.map({ $0.isFinite && $0 >= segment.timestamp && $0 <= end + 1 }) ?? true else { return false }
    }
    for block in checkpoint.blocks[blocks] {
      guard let time = block.time, time.isFinite, time >= chunk.start, time <= end, block.page == nil else { return false }
    }
    return true
  }

  private static func fingerprint(id: String, checkpoint: SourceMediaCheckpoint,
                                   segments: Range<Int>, blocks: Range<Int>) -> String? {
    hash(Payload(id: id, segments: Array((checkpoint.segments ?? [])[segments]), blocks: Array(checkpoint.blocks[blocks])))
  }

  private static func hash<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(value) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct Identity: Encodable {
    var specification = "settled-media-chunk-v1"
    var sourceBinding: String
    var index: Int
    var start: TimeInterval
    var duration: TimeInterval
  }

  private struct Payload: Encodable {
    var id: String
    var segments: [TranscriptSegment]
    var blocks: [ProjectSourceText]
  }
}
