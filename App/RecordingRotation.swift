import Foundation

/// The next file may receive samples only after this transition is durable.
struct RecordingRotation: Sendable {
  var previous: RecordingAudioManifest
  var next: RecordingAudioManifest

  static func make(previous: RecordingAudioManifest, closedFrames: Int64, nextFileName: String) -> Self? {
    guard previous.isValid(for: previous.recordingID), previous.parts.count < RecordingAudioManifest.maximumParts,
          let last = previous.parts.last, last.state == .writing, closedFrames > 0,
          closedFrames < Int64(previous.sampleRate) * 86_400 - last.frameOffset else { return nil }
    var next = previous
    next.parts[next.parts.count - 1].frameCount = closedFrames
    next.parts[next.parts.count - 1].state = .finalized
    next.parts.append(.init(fileName: nextFileName, frameOffset: last.frameOffset + closedFrames,
      frameCount: nil, state: .writing))
    guard next.isValid(for: previous.recordingID) else { return nil }
    return Self(previous: previous, next: next)
  }

  var isValid: Bool {
    guard next.parts.count == previous.parts.count + 1, let name = next.parts.last?.fileName,
          let frames = next.parts.dropLast().last?.frameCount,
          let rebuilt = Self.make(previous: previous, closedFrames: frames, nextFileName: name) else { return false }
    return rebuilt.next == next
  }
}
