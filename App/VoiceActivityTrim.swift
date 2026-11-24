import AVFoundation
import Foundation

/// The file that is sent to a transcription engine, and what it holds.
///
/// The stored recording is never replaced. The trim is a separate temporary
/// file that exists only for the request, and it keeps the original's
/// sample rate and channel count so the recogniser sees the same kind of
/// audio it would have seen.
struct VoiceActivityTrim: Sendable {
  var url: URL
  var timeline: VoiceActivityTimeline
}

/// Removes the silent parts of a recording before it is transcribed.
///
/// The silence is measured with the bundled voice activity model. The
/// written file keeps the original sample rate and channel count, so no
/// conversion quality is lost, and the original recording on disk is never
/// touched. A failure never stops the transcription: the caller keeps the
/// original audio.
enum VoiceActivityTrimmer {
  private static let maximumBytes = 100 * 1_024 * 1_024
  private static let minimumDuration: TimeInterval = 60

  /// The trimmed audio for one recording.
  ///
  /// It is nil when the model is unavailable, when the recording is shorter
  /// than a minute, or when trimming failed. In every one of those cases the
  /// caller transcribes the original audio.
  static func trimmedAudio(for url: URL, directory: URL) async -> VoiceActivityTrim? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let original = duration(of: url), original >= minimumDuration,
          original <= VoiceActivityTimeline.maximumDuration,
          let originalBytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          let model = await VoiceActivityModelAssets.shared.model() else { return nil }
    let timeline: VoiceActivityTimeline
    do {
      timeline = try await FluidVoiceActivityEvaluator(model: model).evaluate(url)
    } catch {
      return nil
    }
    // A recording with nothing to remove is not rewritten.
    guard timeline.duration + 1 < original else { return nil }
    let output = directory.appendingPathComponent("trimmed-\(UUID().uuidString).m4a")
    var keepOutput = false
    defer { if !keepOutput { try? FileManager.default.removeItem(at: output) } }
    do {
      try write(timeline: timeline, from: url, to: output)
    } catch {
      return nil
    }
    guard let trimmed = duration(of: output), abs(trimmed - timeline.duration) < 0.25,
          let bytes = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          bytes > 0, bytes < originalBytes, bytes <= maximumBytes else { return nil }
    keepOutput = true
    return VoiceActivityTrim(url: output, timeline: timeline)
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
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
      throw SourceMediaFailure.invalidTemporaryFile
    }
    let writer = try AVAudioFile(forWriting: output, settings: [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 96_000,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    for range in timeline.ranges {
      let start = AVAudioFramePosition(range.start * format.sampleRate)
      guard start >= 0, start < file.length else { throw SourceMediaFailure.invalidTemporaryFile }
      var frames = min(AVAudioFramePosition(range.duration * format.sampleRate), file.length - start)
      file.framePosition = start
      while frames > 0 {
        try Task.checkCancellation()
        let count = AVAudioFrameCount(min(frames, AVAudioFramePosition(buffer.frameCapacity)))
        try file.read(into: buffer, frameCount: count)
        guard buffer.frameLength == count else { throw SourceMediaFailure.invalidTemporaryFile }
        try writer.write(from: buffer)
        frames -= AVAudioFramePosition(count)
      }
    }
  }
}
