import AVFAudio
import Foundation

@MainActor
final class LiveSpeechRenderer {
  private let synthesizer = AVSpeechSynthesizer()
  private var continuation: AsyncThrowingStream<LiveAudioChunk, Error>.Continuation?
  private var requestID: UUID?

  func stream(_ text: String) throws -> AsyncThrowingStream<LiveAudioChunk, Error> {
    stop()
    guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else {
      throw LiveVoiceError.unavailable("日本語の読み上げ音声を利用できません。端末の音声設定をご確認ください。")
    }
    let request = UUID()
    requestID = request
    let (stream, continuation) = AsyncThrowingStream<LiveAudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
    self.continuation = continuation
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor in
        guard self?.requestID == request else { return }
        self?.stop()
      }
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.write(utterance) { buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer else {
        continuation.finish(throwing: LiveVoiceError.unavailable("読み上げ音声を生成できませんでした。"))
        return
      }
      guard pcm.frameLength > 0 else { continuation.finish(); return }
      guard let chunk = LiveAudioChunk(buffer: pcm) else {
        continuation.finish(throwing: LiveVoiceError.unavailable("読み上げの音声形式を利用できません。"))
        return
      }
      if case .dropped = continuation.yield(chunk) {
        continuation.finish(throwing: LiveVoiceError.unavailable("読み上げが追いつかなかったため停止しました。"))
      }
    }
    return stream
  }

  func stop() {
    requestID = nil
    let previous = continuation
    continuation = nil
    synthesizer.stopSpeaking(at: .immediate)
    previous?.finish()
  }
}
