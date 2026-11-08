import AVFAudio
import Dispatch
import Foundation
import Synchronization

/// Owns one microphone tap for a recording run. The audio session is already
/// active (see `AudioRecorderService`); this type never changes it and never
/// installs a second tap. It converts the real hardware format to the writer's
/// 44.1 kHz mono Float32 timeline and hands owned buffers to the recording sink
/// first, then to an optional live sink.
///
/// The tap only converts and hands off. It does no file, SQLite or UI work;
/// `RecordingChunkWriter` copies into its bounded stream and returns false when
/// the producer must stop.
final class RecordingMicrophoneInput: @unchecked Sendable {
  struct Output: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer
    /// Position in the 44.1 kHz target timeline, derived from received frames.
    var startFrame: Int64
  }

  enum Failure: Error, Sendable, Equatable {
    case noInput
    case unsupportedFormat
    case conversion
    case inputGap
    case inputDuplicate
    case overrun
  }

  static let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!

  /// Returns false when the recording can no longer accept input, so capture
  /// must stop instead of dropping samples silently.
  typealias Sink = @Sendable (Output) -> Bool

  private let engine: AVAudioEngine
  private let sink: Sink
  private let liveSink: (@Sendable (AVAudioPCMBuffer) -> Void)?
  private let onFailure: @Sendable (Failure) -> Void
  private let accepting = Mutex(false)
  private let timing = Mutex(AudioTapTiming())
  private var isInstalled = false
  /// Hardware format the current tap was installed with; read by the service to
  /// detect a route change that needs the tap (and converter) rebuilt.
  private(set) var installedFormat: AVAudioFormat?
  /// Touched only inside the serial input tap for the current run.
  private var continuity = RecordingInputContinuity()
  private var framePosition: Int64 = 0

  init(sink: @escaping Sink, liveSink: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil,
       onFailure: @escaping @Sendable (Failure) -> Void) {
    engine = AVAudioEngine()
    self.sink = sink
    self.liveSink = liveSink
    self.onFailure = onFailure
  }

  deinit {
    if isInstalled {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
  }

  /// Call only after the shared session is active. The engine's real output
  /// format is read here; 44.1 kHz is not assumed. On resume pass
  /// `resetTimeline: false` so the writer continues the same frame timeline.
  func start(resetTimeline: Bool = true) throws {
    guard !isInstalled else { return }
    let input = engine.inputNode
    let hardware = input.inputFormat(forBus: 0)
    let format = input.outputFormat(forBus: 0)
    guard hardware.sampleRate.isFinite, hardware.sampleRate > 0, hardware.channelCount > 0,
          format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
          format.sampleRate == hardware.sampleRate else { throw Failure.noInput }
    guard let converter = LiveAudioBufferConverter(source: format, target: Self.targetFormat) else {
      throw Failure.unsupportedFormat
    }
    continuity.reset()
    installedFormat = format
    if resetTimeline { framePosition = 0 }
    accepting.withLock { $0 = true }
    input.installTap(onBus: 0, bufferSize: 4_096, format: format) { @Sendable [weak self] buffer, when in
      self?.receive(buffer, when: when, converter: converter)
    }
    isInstalled = true
    engine.prepare()
    do {
      try engine.start()
    } catch {
      stop()
      throw Failure.noInput
    }
  }

  /// Call after the recording sink has stopped accepting. Removes the tap so no
  /// further callback runs; the writer drains what it already accepted.
  func stop() {
    accepting.withLock { $0 = false }
    installedFormat = nil
    guard isInstalled else { return }
    isInstalled = false
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  var hasInstalledTap: Bool { isInstalled }

  /// Duration percentiles for the tap callbacks of this run, in microseconds.
  var tapTiming: AudioTapTiming.Summary? { timing.withLock { $0.summary } }

  private func receive(_ buffer: AVAudioPCMBuffer, when: AVAudioTime,
                       converter: LiveAudioBufferConverter) {
    let started = DispatchTime.now().uptimeNanoseconds
    defer {
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000
      timing.withLock { $0.record(microseconds: elapsed) }
    }
    guard accepting.withLock({ $0 }) else { return }
    switch continuity.observe(
      sampleTime: when.isSampleTimeValid ? when.sampleTime : nil,
      frames: buffer.frameLength) {
    case .gap:
      fail(.inputGap)
      return
    case .duplicate:
      fail(.inputDuplicate)
      return
    case .first, .continuous, .empty, .unchecked:
      break
    }
    guard buffer.frameLength > 0 else { return }
    do {
      guard let converted = try converter.convert(buffer) else { return }
      let output = Output(buffer: converted, startFrame: framePosition)
      guard sink(output) else {
        fail(.overrun)
        return
      }
      framePosition += Int64(converted.frameLength)
      liveSink?(converted)
    } catch {
      fail(.conversion)
    }
  }

  private func fail(_ failure: Failure) {
    accepting.withLock { $0 = false }
    onFailure(failure)
  }
}
