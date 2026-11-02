import Foundation

enum AudioPlaybackInput: Hashable, Sendable {
  case file(URL)
  case parts(RecordingAudioManifest, directory: URL)

  var scopeURL: URL {
    switch self {
    case .file(let url): url
    case .parts(_, let directory): directory
    }
  }
}
