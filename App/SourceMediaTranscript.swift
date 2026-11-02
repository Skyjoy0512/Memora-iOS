import Foundation

struct SourceMediaTranscript {
  private(set) var blocks: [ProjectSourceText] = []
  private var encodedBytes = 2

  mutating func append(_ segments: [TranscriptSegment], chunk: SourceMediaChunk) throws {
    let encoder = JSONEncoder()
    for segment in segments {
      try Task.checkCancellation()
      // Speech timestamps refer to the exported chunk, not the original player.
      // Allow only the small rounding error at an encoded audio boundary.
      guard segment.timestamp.isFinite, segment.timestamp >= 0,
            segment.timestamp <= chunk.duration + 1 else { throw SourceMediaFailure.invalidTranscript }
      let time = chunk.start + min(segment.timestamp, chunk.duration)
      for block in SourceTextChunks.split(segment.text, time: time) {
        let added = try encoder.encode(block).count + (blocks.isEmpty ? 0 : 1)
        guard added <= ProjectSourceTextReader.maximumBytes - encodedBytes else {
          throw SourceMediaFailure.transcriptTooLarge
        }
        encodedBytes += added
        blocks.append(block)
      }
    }
  }
}
