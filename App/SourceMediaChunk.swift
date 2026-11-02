import Foundation

struct SourceMediaChunk: Sendable {
  static let maximumDuration: TimeInterval = 6 * 60 * 60
  static let durationPerChunk: TimeInterval = 15 * 60

  var start: TimeInterval
  var duration: TimeInterval

  static func plan(duration: TimeInterval) throws -> [Self] {
    guard duration.isFinite, duration > 0, duration <= maximumDuration else {
      throw SourceMediaFailure.invalidDuration
    }
    var chunks: [Self] = []
    var start: TimeInterval = 0
    while start < duration {
      let length = min(durationPerChunk, duration - start)
      chunks.append(Self(start: start, duration: length))
      start += length
    }
    return chunks
  }
}
