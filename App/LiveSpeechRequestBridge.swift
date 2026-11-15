import AVFAudio
import Foundation
@preconcurrency import Speech

/// The audio tap and recognition replacement share this one locked request.
final class LiveSpeechRequestBridge: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?

  func replace(with request: SFSpeechAudioBufferRecognitionRequest?) {
    lock.lock()
    self.request = request
    lock.unlock()
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    request?.append(buffer)
    lock.unlock()
  }
}
