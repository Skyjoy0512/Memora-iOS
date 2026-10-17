import AVFAudio
import Foundation
import Observation

/// Reads a finished answer aloud with the system voice, the way the read-aloud
/// action does in the source app. It shares the audio session through
/// `AudioSessionCoordinator`, so it never sounds on top of a recording and a
/// recording can silence it before taking the session.
@MainActor
@Observable
final class AnswerSpeechService {
  /// The answer being read, or nil.
  private(set) var speakingMessageID: UUID?
  /// Shown when the voice could not start.
  private(set) var errorMessage: String?

  @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
  @ObservationIgnored private let finishDelegate = SpeechFinishDelegate()
  /// The session claim this reading holds, so only this reading gives it up.
  @ObservationIgnored private var sessionToken: AudioSessionCoordinator.Token?
  /// The coordinator's handle for silencing this reading when another player
  /// takes over.
  @ObservationIgnored private var playbackPauserID: UUID?

  init() {
    finishDelegate.onFinish = { [weak self] in
      Task { @MainActor in self?.stop() }
    }
    synthesizer.delegate = finishDelegate
    // Registered once, so a recording can silence a reading before it takes the
    // session. The handler holds this service weakly.
    AudioSessionCoordinator.shared.registerStopper(.playback) { [weak self] in
      self?.stop()
    }
  }

  /// Reads this answer, or stops if it is the one already playing.
  func toggle(messageID: UUID, text: String) {
    if speakingMessageID == messageID {
      stop()
    } else {
      speak(messageID: messageID, text: text)
    }
  }

  func stop() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    speakingMessageID = nil
    if let playbackPauserID {
      AudioSessionCoordinator.shared.unregisterPlaybackPauser(playbackPauserID)
      self.playbackPauserID = nil
    }
    // Gives the session back only for this reading's own claim, so stopping it
    // cannot silence a recording or a newer playback.
    if let sessionToken {
      AudioSessionCoordinator.shared.release(sessionToken)
      self.sessionToken = nil
    }
  }

  func clearError() {
    errorMessage = nil
  }

  private func speak(messageID: UUID, text: String) {
    let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !spoken.isEmpty else { return }
    stop()
    guard let token = AudioSessionCoordinator.shared.claim(.playback) else {
      errorMessage = AudioSessionCoordinator.shared.refusal(for: .playback)
        ?? "今は読み上げできません。"
      return
    }
    sessionToken = token

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)
    } catch {
      AudioSessionCoordinator.shared.release(token)
      sessionToken = nil
      errorMessage = "読み上げを開始できませんでした。"
      return
    }

    speakingMessageID = messageID
    if playbackPauserID == nil {
      playbackPauserID = AudioSessionCoordinator.shared.registerPlaybackPauser { [weak self] in
        self?.stop()
      }
    }
    let utterance = AVSpeechUtterance(string: spoken)
    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
  }
}

/// Reports when the system voice finishes or is interrupted, so the service can
/// give the session back. It only forwards; the service decides what to do.
private final class SpeechFinishDelegate: NSObject, AVSpeechSynthesizerDelegate {
  var onFinish: (() -> Void)?

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    onFinish?()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    onFinish?()
  }
}
