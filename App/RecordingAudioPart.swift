import Foundation

struct RecordingAudioPart: Codable, Hashable, Sendable {
  enum State: String, Codable, Hashable, Sendable { case writing, finalized }

  var fileName: String
  var frameOffset: Int64
  var frameCount: Int64?
  var state: State
}
