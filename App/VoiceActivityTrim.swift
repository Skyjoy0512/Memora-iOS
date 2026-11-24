import AVFoundation
import Foundation

/// The file that is sent to a transcription engine, and what it holds.
///
/// The stored recording is never replaced. The trim is a separate temporary
/// file that exists only for the request, and it keeps the original's
/// sample rate and channel count so the recogniser sees the same kind of
/// audio it would have seen.
struct VoiceActivityTrim: Sendable {
  /// The trimmed audio. Nil when nothing had to be removed.
  var url: URL?
  /// How long the trimmed audio is.
  var duration: TimeInterval
  /// How long the original audio was.
  var originalDuration: TimeInterval
  /// Where speech was in the original. It maps a trimmed time back onto the
  /// original recording, so a removed silence never shifts a timestamp.
  var timeline: VoiceActivityTimeline?

  /// Whether the trim actually shortened anything.
  var isTrimmed: Bool {
    guard let url else { return false }
    return duration + 0.5 < originalDuration
  }
}

/// Removes the silent parts of a recording before it is transcribed.
///
/// The silence is measured with the bundled voice activity model. The
/// written file keeps the original sample rate and channel count, so no
/// conversion quality is lost, and the original recording on disk is never
/// touched. A failure never stops the transcription: the caller keeps the
/// original audio.
enum VoiceActivityTrimmer {
  /// The maximum size of the trimmed file, in bytes.
  static let maximumBytes: Int64 = 100 * 1_024 * 1_024
  /// A recording shorter than this is never rewritten.
  static let minimumDuration: TimeInterval = 60

  /// The trimmed audio for one recording.
  ///
  /// It is nil when the model is unavailable, when the recording is shorter
  /// than a minute, or when trimming failed. In every one of those cases the
  /// caller transcribes the original audio.
  static func trimmedAudio(for url: URL, staging: SourceMediaStageLease) async -> VoiceActivityTrim? {
    let original = duration(of: url)
    guard let original, original >= minimumDuration else { return nil }
    guard let model = await VoiceActivityModelAssets.shared.model() else { return nil }
    let timeline: VoiceActivityTimeline
    do {
      timeline = try await FluidVoiceActivityEvaluator(model: model).evaluate(url)
    } catch {
      return nil
    }
    // A recording with nothing to remove is not rewritten.
    let kept = timeline.ranges.reduce(0) { $0 + $1.duration }
    guard kept + 1 < original else { return nil }
    let output = staging.directory.appendingPathComponent("trimmed.m4a")
    do {
      try write(timeline: timeline, from: url, to: output)
    } catch {
      return nil
    }
    guard let trimmed = duration(of: output), trimmed > 0 else { return nil }
    let values = try? output.resourceValues(forKeys: [.fileSizeKey])
    guard let bytes = values?.fileSize, Int64(bytes) > 0, Int64(bytes) <= maximumBytes else { return nil }
    return VoiceActivityTrim(url: output, duration: trimmed, originalDuration: original,
      timeline: timeline)
  }

  private static func duration(of url: URL) -> TimeInterval? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let rate = file.processingFormat.sampleRate
    guard rate > 0 else { return nil }
    return Double(file.length) / rate
  }

  private static func write(timeline: VoiceActivityTimeline, from source: URL, to output: URL) throws {
    let file = try AVAudioFile(forReading: source)
    let format = file.processingFormat
    let writer = try AVAudioFile(forWriting: output, settings: [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 96_000,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    for range in timeline.ranges {
      let start = AVAudioFramePosition(range.start * format.sampleRate)
      guard start >= 0, start < file.length else { continue }
      let frames = AVAudioFrameCount(min(range.duration * format.sampleRate,
        Double(file.length - start)))
      guard frames > 0 else { continue }
      file.framePosition = start
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { continue }
      try file.read(into: buffer, frameCount: frames)
      guard buffer.frameLength > 0 else { continue }
      try writer.write(from: buffer)
    }
  }
}
