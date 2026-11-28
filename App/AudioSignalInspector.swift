import AVFoundation
import Foundation

/// Diagnostics for bounded decoded chunks. This never rewrites the original,
/// normalizes a quiet voice, or classifies music/noise from volume alone.
enum AudioSignalInspector {
  static func inspect(_ url: URL) throws -> AudioSignalReport {
    let diagnostic = AudioProcessingDiagnostics.current
    let span = diagnostic?.begin(.quality)
    var outcome: AudioDiagnosticReport.Outcome = .failed
    defer { diagnostic?.end(span, outcome: Task.isCancelled ? .cancelled : outcome) }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard format.sampleRate.isFinite, format.sampleRate > 0, (1...32).contains(format.channelCount),
          file.length > 0, Double(file.length) / format.sampleRate <= SourceMediaChunk.durationPerChunk + 1,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
      throw SourceMediaFailure.invalidTemporaryFile
    }
    var squares = 0.0, peak = 0.0
    var clipped: Int64 = 0, quiet: Int64 = 0, frames: Int64 = 0
    let channelCount = Int(format.channelCount)
    let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Int(buffer.frameCapacity))
    defer { scratch.deallocate() }
    while file.framePosition < file.length {
      try Task.checkCancellation()
      try file.read(into: buffer)
      let count = Int(buffer.frameLength)
      guard count > 0, let channels = buffer.floatChannelData else { throw SourceMediaFailure.invalidTemporaryFile }
      for channel in 0..<channelCount {
        let samples = channels[channel]
        let total = AudioLevelMath.sumOfSquares(samples, count: count)
        // A non-finite sample makes the sum non-finite: the file is refused
        // rather than measured as silence.
        guard total.isFinite else { throw SourceMediaFailure.invalidTemporaryFile }
        squares += Double(total)
        peak = max(peak, Double(AudioLevelMath.peakMagnitude(samples, count: count)))
        clipped += Int64(AudioLevelMath.countMagnitudes(
          atLeast: 0.999, in: samples, count: count, scratch: scratch))
      }
      // -60dBFS is deliberately named quiet, never "no speech". A frame is
      // quiet when every channel is below the threshold.
      if channelCount == 1 {
        quiet += Int64(count) - Int64(AudioLevelMath.countMagnitudes(
          atLeast: 0.001, in: channels[0], count: count, scratch: scratch))
      } else {
        for index in 0..<count {
          var framePeak: Float = 0
          for channel in 0..<channelCount {
            framePeak = max(framePeak, abs(channels[channel][index]))
          }
          if framePeak < 0.001 { quiet += 1 }
        }
      }
      frames += Int64(count)
    }
    let sampleCount = Double(frames) * Double(format.channelCount)
    let rms = sqrt(squares / sampleCount)
    let report = AudioSignalReport(duration: Double(frames) / format.sampleRate,
      sampleRate: format.sampleRate, channels: Int(format.channelCount),
      codec: file.fileFormat.streamDescription.pointee.mFormatID,
      rmsDBFS: rms > 0 ? 20 * log10(rms) : -160, peak: peak,
      clippedSampleFraction: Double(clipped) / sampleCount,
      quietFrameFraction: Double(quiet) / Double(frames), inspectedFrames: frames)
    if diagnostic?.snapshot.kind == .quality { diagnostic?.setAudioSeconds(report.duration) }
    diagnostic?.signal(report)
    outcome = .success
    return report
  }
}
