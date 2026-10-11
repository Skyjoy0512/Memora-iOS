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
    case voiceEnrollment

    var label: String {
      switch self {
      case .recording: "録音"
      case .playback: "再生"
      case .speechInput: "音声入力"
      case .voiceEnrollment: "声の登録"
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
  private(set) var isPreparingRecording = false
  @ObservationIgnored private var ownerTokenID: UUID?
  /// Ways for a feature to be asked to stop before recording takes the session,
  /// each keyed by a token so a replaced service's handler can be removed.
  @ObservationIgnored private var stoppers: [Use: [UUID: @MainActor () async -> Void]] = [:]
  /// Ways to pause a running playback, so a second player taking over silences
  /// the first instead of both sounding at once.
  @ObservationIgnored private var playbackPausers: [UUID: @MainActor () -> Void] = [:]
  private let deactivateSession: @MainActor () -> Void

  init(deactivateSession: (@MainActor () -> Void)? = nil) {
    self.deactivateSession = deactivateSession ?? {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  /// Asks anything else using the session to stop, waits for it to finish, and
  /// only then takes the session for recording, so a recorder never starts on top
  /// of running playback or voice input.
  func beginRecording() async -> Token? {
    guard !isRecording, !isPreparingRecording, !Task.isCancelled else { return nil }
    isPreparingRecording = true
    defer { isPreparingRecording = false }
    let handlers = stoppers.filter { $0.key != .recording }.flatMap { $0.value.values }
    for handler in handlers {
      await handler()
      guard !Task.isCancelled else { return nil }
    }
    guard owner == nil, !isRecording else { return nil }
    return takeRecordingSession()
  }

  func owns(_ token: Token) -> Bool {
    ownerTokenID == token.id && owner == token.use
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

  /// Registers a running player that can be paused when another one takes over.
  @discardableResult
  func registerPlaybackPauser(_ handler: @escaping @MainActor () -> Void) -> UUID {
    let id = UUID()
    playbackPausers[id] = handler
    return id
  }

  func unregisterPlaybackPauser(_ id: UUID) {
    playbackPausers[id] = nil
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
    guard !isPreparingRecording else { return nil }
    if use != .recording, isRecording || owner == .recording {
      return nil
    }
    switch owner {
    case nil:
      owner = use
      let token = Token(id: UUID(), use: use)
      ownerTokenID = token.id
      return token
    case use:
      // A new player taking playback pauses whoever held it, so two recordings
      // spawned from different screens never sound at once.
      if use == .playback {
        for pauser in playbackPausers.values {
          pauser()
        }
      }
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
    if isPreparingRecording {
      return "録音を準備しています。準備が終わるまで\(use.label)を使えません。"
    }
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
    deactivateSession()
  }
}
