import AVFAudio
import Foundation
import Speech

/// Feeds the recording's microphone timeline to the live analyzer. It lives on
/// the audio thread: it converts 44.1 kHz mono to the analyzer format and drops
/// input when the bounded stream is full. A live miss never affects recording.
final class LiveAudioInputFeeder: @unchecked Sendable {
  private let converter: LiveAudioBufferConverter
  private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
  private let diagnostic: AudioDiagnosticSession?

  init?(source: AVAudioFormat, target: AVAudioFormat,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        diagnostic: AudioDiagnosticSession?) {
    guard let converter = LiveAudioBufferConverter(source: source, target: target) else { return nil }
    self.converter = converter
    self.continuation = continuation
    self.diagnostic = diagnostic
  }

  func consume(_ buffer: AVAudioPCMBuffer) {
    do {
      guard let owned = try converter.convert(buffer) else { return }
      if case .dropped = continuation.yield(AnalyzerInput(buffer: owned)) {
        diagnostic?.count(.liveBufferDropped)
        continuation.finish(throwing: CocoaError(.coderInvalidValue))
      }
    } catch {
      continuation.finish(throwing: error)
    }
  }
}
