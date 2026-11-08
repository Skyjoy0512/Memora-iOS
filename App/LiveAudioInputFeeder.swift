import AVFAudio
import Foundation
import Speech

/// Feeds the recording's microphone timeline to the live analyzer off the audio
/// thread. The tap only calls `consume`, which copies into a bounded queue; a
/// dedicated serial consumer converts to the analyzer format and yields into the
/// analyzer stream. Drops, conversion failures and a stopped recognizer affect
/// the live transcript only — the recording keeps writing its original.
final class LiveAudioInputFeeder: @unchecked Sendable {
  private let converter: LiveAudioBufferConverter
  private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
  private let diagnostic: AudioDiagnosticSession?
  private let queue: LiveAudioBufferQueue
  private var consumer: Task<Void, Never>?

  init?(source: AVAudioFormat, target: AVAudioFormat,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        diagnostic: AudioDiagnosticSession?) {
    guard let converter = LiveAudioBufferConverter(source: source, target: target) else { return nil }
    self.converter = converter
    self.continuation = continuation
    self.diagnostic = diagnostic
    let queue = LiveAudioBufferQueue()
    self.queue = queue
    // Capture the dependencies, not `self`, so the consumer cannot keep the
    // feeder alive after it is replaced and finished.
    let diagnostic = diagnostic
    consumer = Task.detached(priority: .userInitiated) {
      await LiveAudioInputFeeder.consume(queue, converter: converter,
        continuation: continuation, diagnostic: diagnostic)
    }
  }

  deinit {
    finish()
    consumer?.cancel()
  }

  /// Called from the recording tap. Copies and enqueues only.
  func consume(_ buffer: AVAudioPCMBuffer) {
    switch queue.enqueue(buffer) {
    case .enqueued, .ignored, .closed:
      break
    case .dropped:
      diagnostic?.count(.liveBufferDropped)
    }
  }

  /// Stops accepting input. Buffers already accepted are drained and converted
  /// in order; the stream then ends so the consumer exits.
  func finish() {
    queue.finish()
  }

  var stats: LiveAudioBufferQueue.Stats { queue.stats }

  private static func consume(_ queue: LiveAudioBufferQueue,
                              converter: LiveAudioBufferConverter,
                              continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
                              diagnostic: AudioDiagnosticSession?) async {
    for await owned in queue.buffers {
      if Task.isCancelled { return }
      queue.markConsumed()
      do {
        guard let converted = try converter.convert(owned.buffer) else { continue }
        switch continuation.yield(AnalyzerInput(buffer: converted)) {
        case .enqueued:
          break
        case .dropped:
          diagnostic?.count(.liveBufferDropped)
          continuation.finish(throwing: CocoaError(.coderInvalidValue))
          return
        case .terminated:
          return
        @unknown default:
          return
        }
      } catch {
        diagnostic?.count(.liveConversionFailure)
        continuation.finish(throwing: error)
        return
      }
    }
  }
}
