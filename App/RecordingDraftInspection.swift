import Foundation

struct RecordingDraftInspection {
  var playbackURL: URL?
  var duration: TimeInterval?
  var manifest: RecordingAudioManifest?
  var notice: String

  var canProcess: Bool { playbackURL != nil && duration != nil }
}
