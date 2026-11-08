import AVFAudio
import Foundation
import Synchronization

/// Bounded handoff from the microphone tap to the live analyzer's serial
/// consumer. `enqueue` only copies the already-converted PCM and appends it; it
/// never converts, waits or touches the analyzer, so a slow live path cannot
/// extend the recording callback. When the queue is full the newest buffer is
/// dropped and counted; the recording writer is never involved.
final class LiveAudioBufferQueue: @unchecked Sendable {
  struct OwnedBuffer: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
  }

  enum EnqueueResult: Sendable, Equatable {
    case enqueued
    case dropped
    case ignored
    case closed
  }

  struct Stats: Sendable, Equatable {
    var enqueued = 0
    var dropped = 0
    var consumed = 0
    var isFinished = false
  }

  static let defaultCapacity = 16

  let buffers: AsyncStream<OwnedBuffer>
  private let continuation: AsyncStream<OwnedBuffer>.Continuation
  private let state: Mutex<Stats>

  init(capacity: Int = LiveAudioBufferQueue.defaultCapacity) {
    let limit = max(1, capacity)
    let (stream, continuation) = AsyncStream<OwnedBuffer>.makeStream(
      bufferingPolicy: .bufferingOldest(limit))
    buffers = stream
    self.continuation = continuation
    state = Mutex(Stats())
  }

  /// Copies on the caller's thread (the tap) because an AVAudioEngine tap reuses
  /// its own storage, then hands the copy to the bounded queue without waiting.
  func enqueue(_ buffer: AVAudioPCMBuffer) -> EnqueueResult {
    guard !state.withLock({ $0.isFinished }) else { return .closed }
    guard buffer.frameLength > 0 else { return .ignored }
    guard let copy = Self.copy(buffer) else {
      state.withLock { $0.dropped += 1 }
      return .dropped
    }
    switch continuation.yield(OwnedBuffer(buffer: copy)) {
    case .enqueued:
      state.withLock { $0.enqueued += 1 }
      return .enqueued
    case .dropped:
      state.withLock { $0.dropped += 1 }
      return .dropped
    case .terminated:
      return .closed
    @unknown default:
      return .closed
    }
  }

  func markConsumed() {
    state.withLock { $0.consumed += 1 }
  }

  var stats: Stats { state.withLock { $0 } }

  /// Ends the stream; the consumer drains what was already accepted and exits.
  func finish() {
    let alreadyFinished = state.withLock { stats -> Bool in
      defer { stats.isFinished = true }
      return stats.isFinished
    }
    guard !alreadyFinished else { return }
    continuation.finish()
  }

  private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let source = buffer.floatChannelData,
          let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
          let destination = copy.floatChannelData else { return nil }
    for channel in 0..<Int(buffer.format.channelCount) {
      memcpy(destination[channel], source[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
    copy.frameLength = buffer.frameLength
    return copy
  }
}
