import Foundation

/// Silence is normal; missing callbacks or sustained unrecognised audio aren't.
struct LiveInputHealth {
  enum Failure: Equatable {
    case noMicrophoneBuffers
    case recognitionStalled

    var message: String {
      switch self {
      case .noMicrophoneBuffers:
        "マイクから音声が届いていません。接続中のイヤホンやBluetoothの入力先を確認して、Liveを再開してください。"
      case .recognitionStalled:
        "音は届いていますが、日本語を認識できませんでした。静かな場所でマイクに近づき、Liveを再開してください。"
      }
    }
  }

  private var lastFrames = 0
  private var lastAudioAt: TimeInterval = 0
  private var firstVoiceAt: TimeInterval?
  private var lastResultAt: TimeInterval = 0
  private var voiceBaseline: Double = 0
  private var resetsVoiceBaseline = false

  mutating func receivedResult(at elapsed: TimeInterval) {
    lastResultAt = elapsed
    firstVoiceAt = nil
    // A result may arrive between meter polls; include that poll's audio in
    // the recognised baseline instead of treating it as a new unheard phrase.
    resetsVoiceBaseline = true
  }

  mutating func check(elapsed: TimeInterval, frames: Int, voicedSeconds: Double,
                      expectsRecognition: Bool) -> Failure? {
    if frames > lastFrames { lastAudioAt = elapsed }
    lastFrames = frames
    if elapsed - lastAudioAt >= 3 { return .noMicrophoneBuffers }
    if resetsVoiceBaseline {
      voiceBaseline = voicedSeconds
      resetsVoiceBaseline = false
    }
    guard expectsRecognition else {
      firstVoiceAt = nil
      voiceBaseline = voicedSeconds
      return nil
    }
    if voicedSeconds - voiceBaseline >= 0.8, firstVoiceAt == nil { firstVoiceAt = elapsed }
    if let firstVoiceAt, elapsed - max(firstVoiceAt, lastResultAt) >= 15 { return .recognitionStalled }
    return nil
  }
}
