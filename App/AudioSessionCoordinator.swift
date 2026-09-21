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

  /// One claim on the session. The holder is the token, not the feature name, so
  /// a late callback from an old run cannot give up a newer run's session.
  struct Token: Equatable {
    let id: UUID
    let use: Use
  }

  private(set) var owner: Use?
  private(set) var isRecording = false
  private var ownerTokenID: UUID?
  /// Ways for a feature to be asked to stop before recording takes the session,
  /// each keyed by a token so a replaced service's handler can be removed.
  private var stoppers: [Use: [UUID: @MainActor () async -> Void]] = [:]

  /// Asks anything else using the session to stop, waits for it to finish, and
  /// only then takes the session for recording, so a recorder never starts on top
  /// of running playback or voice input.
  func beginRecording() async -> Token {
    for (use, handlers) in stoppers where use != .recording {
      for handler in handlers.values {
        await handler()
      }
    }
    return takeRecordingSession()
  }

  /// Takes the session for recording without waiting on other users, for a resume
  /// after an interruption, where this recorder already owns it.
  @discardableResult
  func takeRecordingSession() -> Token {
    isRecording = true
    owner = .recording
    let token = Token(id: UUID(), use: .recording)
    ownerTokenID = token.id
    return token
  }

  /// Registers a stop request for `use` and returns a token to remove it.
  @discardableResult
  func registerStopper(_ use: Use, _ handler: @escaping @MainActor () async -> Void) -> UUID {
    let id = UUID()
    stoppers[use, default: [:]][id] = handler
    return id
  }

  func unregisterStopper(_ id: UUID, for use: Use) {
    stoppers[use]?[id] = nil
  }

  /// Ends the recording, but only for the token that began it.
  func endRecording(_ token: Token) {
    guard token.use == .recording, ownerTokenID == token.id else { return }
    isRecording = false
    if owner == .recording {
      owner = nil
    }
    ownerTokenID = nil
    deactivate()
  }

  /// Takes the session for `use`, or explains why it cannot. Recording wins over
  /// everything; otherwise the session may only be taken when it is free. A new
  /// claim for the same feature invalidates the previous one.
  func claim(_ use: Use) -> Token? {
    if use != .recording, isRecording || owner == .recording {
      return nil
    }
    switch owner {
    case nil, use:
      owner = use
      let token = Token(id: UUID(), use: use)
      ownerTokenID = token.id
      return token
    default:
      return nil
    }
  }

  /// Gives the session back, but only for the token that holds it. A recording
  /// is ended through `endRecording(_:)` alone, so a stray release cannot leave a
  /// running recording without the session.
  func release(_ token: Token) {
    guard token.use != .recording else { return }
    guard ownerTokenID == token.id, owner == token.use else { return }
    owner = nil
    ownerTokenID = nil
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
