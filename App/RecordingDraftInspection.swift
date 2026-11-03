import Foundation

struct RecordingDraftInspection {
  var playbackURL: URL?
  var duration: TimeInterval?
  var manifest: RecordingAudioManifest?
  var notice: String

  var canProcess: Bool {
    guard let duration else { return false }
    return playbackURL != nil || ((manifest?.parts.count ?? 0) > 1 && manifest?.finalizedDuration == duration)
  }
}
