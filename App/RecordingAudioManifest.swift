import Foundation

/// Positions count original audio frames, never wall-clock time or live text.
struct RecordingAudioManifest: Codable, Hashable, Sendable {
  var version = 1
  var recordingID: UUID
  var sampleRate: Int
  var parts: [RecordingAudioPart]

  static let maximumParts = 128

  static func starting(id: UUID, fileName: String) -> Self {
    Self(recordingID: id, sampleRate: 44_100,
      parts: [.init(fileName: fileName, frameOffset: 0, frameCount: nil, state: .writing)])
  }

  var fileNames: [String] { parts.map(\.fileName) }

  func isValid(for id: UUID, activeFileName: String? = nil) -> Bool {
    guard version == 1, recordingID == id, (8_000...192_000).contains(sampleRate),
          !parts.isEmpty, parts.count <= Self.maximumParts,
          activeFileName == nil || parts.last?.fileName == activeFileName else { return false }
    var next: Int64 = 0
    var names: Set<String> = []
    let maximumFrames = Int64(sampleRate) * 86_400
    for (index, part) in parts.enumerated() {
      let name = part.fileName
      guard !name.isEmpty, name.utf8.count <= 255, name != ".", name != "..", !name.contains("/"),
            !name.contains("\\"), !name.contains("\0"), names.insert(name).inserted,
            part.frameOffset == next, next < maximumFrames else { return false }
      switch part.state {
      case .writing:
        guard index == parts.count - 1, part.frameCount == nil else { return false }
      case .finalized:
        guard let frames = part.frameCount, frames > 0, frames <= maximumFrames - next else { return false }
        next += frames
      }
    }
    return true
  }

  func finalized(frameCounts: [Int64]) -> Self? {
    guard isValid(for: recordingID), frameCounts.count == parts.count else { return nil }
    var result = self
    let maximumFrames = Int64(sampleRate) * 86_400
    for index in parts.indices {
      let frames = frameCounts[index], part = parts[index]
      guard frames > 0, frames <= maximumFrames - part.frameOffset,
            part.frameCount == nil || part.frameCount == frames else { return nil }
      result.parts[index].frameCount = frames
      result.parts[index].state = .finalized
    }
    return result.isValid(for: recordingID) ? result : nil
  }

  var finalizedDuration: TimeInterval? {
    guard isValid(for: recordingID), let last = parts.last, last.state == .finalized,
          let frames = last.frameCount else { return nil }
    return Double(last.frameOffset + frames) / Double(sampleRate)
  }

  func preservesTimeline(of previous: Self) -> Bool {
    guard isValid(for: previous.recordingID), version == previous.version,
          sampleRate == previous.sampleRate, parts.count == previous.parts.count else { return false }
    return zip(previous.parts, parts).allSatisfy { before, after in
      before.fileName == after.fileName && before.frameOffset == after.frameOffset &&
        (before.frameCount == nil || before.frameCount == after.frameCount)
    }
  }
}
