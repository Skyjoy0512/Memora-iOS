import AVFAudio
import Foundation
import Observation

/// Who is allowed to use the shared audio session right now. Recording has the
/// first claim: nothing else may take the session while it runs, and only the
/// feature that took the session may give it up again — so a text question or a
/// screen closing cannot switch off a recording's audio.
@MainActor
@Observable
final class AudioSessionCoordinator {
  static let shared = AudioSessionCoordinator()

  enum Use: String {
    case recording
    case playback
    case speechInput

    var label: String {
      switch self {
      case .recording: "録音"
      case .playback: "再生"
      case .speechInput: "音声入力"
      }
    }
  }

  private(set) var owner: Use?
  private(set) var isRecording = false

  /// True while some other feature holds the session.
  private var isBusy: Bool {
    guard let owner else { return false }
    return owner != .recording || isRecording
  }

  /// A recording starting takes the session from anything else.
  func beginRecording() {
    isRecording = true
    owner = .recording
  }

  func endRecording() {
    isRecording = false
    if owner == .recording {
      owner = nil
    }
    deactivate()
  }

  /// Takes the session for `use`, or explains why it cannot. Recording wins over
  /// everything; otherwise the session may only be taken when it is free.
  func claim(_ use: Use) -> Bool {
    if use != .recording, isRecording || owner == .recording {
      return false
    }
    switch owner {
    case nil, use:
      owner = use
      return true
    default:
      return false
    }
  }

  /// Gives the session back, but only if this feature is the one holding it.
  /// A recording is ended through `endRecording()` alone, so a stray release
  /// cannot leave a running recording without the session.
  func release(_ use: Use) {
    guard use != .recording else { return }
    guard owner == use else { return }
    owner = nil
    deactivate()
  }

  /// What to tell the person when `use` cannot run now.
  func refusal(for use: Use) -> String? {
    if isRecording || owner == .recording {
      return "録音中は\(use.label)を使えません。録音を終えてからお試しください。"
    }
    if let owner, owner != use {
      return "\(owner.label)中は\(use.label)を使えません。先に\(owner.label)を終えてください。"
    }
    return nil
  }

  /// Switching the session off is only safe when nobody is using it.
  private func deactivate() {
    guard owner == nil, !isRecording else { return }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
