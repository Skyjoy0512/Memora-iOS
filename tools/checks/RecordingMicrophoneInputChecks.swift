import AVFAudio
import Foundation

@main
enum RecordingMicrophoneInputChecks {
  static func main() throws {
    // The target timeline is fixed and matches what RecordingChunkWriter accepts.
    let target = RecordingMicrophoneInput.targetFormat
    precondition(target.sampleRate == 44_100 && target.channelCount == 1)
    precondition(target.commonFormat == .pcmFormatFloat32 && !target.isInterleaved)

    // Continuity: a dropped or repeated host buffer is reported, never merged.
    var continuity = RecordingInputContinuity()
    precondition(continuity.observe(sampleTime: nil, frames: 100) == .unchecked)
    precondition(continuity.observe(sampleTime: 0, frames: 100) == .first)
    continuity.reset()
    precondition(continuity.observe(sampleTime: 0, frames: 100) == .first)
    precondition(continuity.observe(sampleTime: 100, frames: 100) == .continuous)
    precondition(continuity.observe(sampleTime: 250, frames: 100) == .gap)
    precondition(continuity.observe(sampleTime: 250, frames: 100) == .duplicate)
    precondition(continuity.observe(sampleTime: 350, frames: 100) == .continuous)
    precondition(continuity.observe(sampleTime: 350, frames: 0) == .empty)
    precondition(continuity.observe(sampleTime: 450, frames: 100) == .continuous)
    continuity.reset()
    precondition(continuity.observe(sampleTime: 900, frames: 10) == .first)

    // A missing clock cannot be checked, and resumes as unverified rather than
    // pretending the previous timeline continued.
    var unchecked = RecordingInputContinuity()
    precondition(unchecked.observe(sampleTime: 0, frames: 10) == .first)
    precondition(unchecked.observe(sampleTime: nil, frames: 10) == .unchecked)
    precondition(unchecked.observe(sampleTime: 20, frames: 10) == .first)

    // Real hardware may not be 44.1 kHz: the converter produces the target
    // format and owned storage, and a passthrough keeps sample identity.
    let source = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    guard let converter = LiveAudioBufferConverter(source: source, target: target) else {
      preconditionFailure("48 kHz mono must convert to the writer format")
    }
    let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4_800)!
    input.frameLength = 4_800
    for frame in 0..<Int(input.frameLength) {
      input.floatChannelData![0][frame] = sin(Float(frame) * 0.05) * 0.1
    }
    // Streaming conversion buffers a few input frames, so the ratio is checked
    // over a run of buffers rather than on the first one.
    var totalInput = 0
    var totalOutput = 0
    for _ in 0..<50 {
      guard let converted = try converter.convert(input) else {
        preconditionFailure("conversion produced no audio")
      }
      precondition(converted.format == target && converted.frameLength > 0)
      for frame in 0..<Int(converted.frameLength) {
        precondition(converted.floatChannelData![0][frame].isFinite)
      }
      totalInput += Int(input.frameLength)
      totalOutput += Int(converted.frameLength)
    }
    let ratio = Double(totalOutput) / Double(totalInput)
    precondition(abs(ratio - 44_100.0 / 48_000.0) < 0.01,
      "streamed resampling did not track the sample-rate ratio")

    // Stereo hardware is downmixed, not rejected.
    let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    guard let downmix = LiveAudioBufferConverter(source: stereo, target: target) else {
      preconditionFailure("stereo input must be accepted")
    }
    let stereoSamples = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 960)!
    stereoSamples.frameLength = 960
    for channel in 0..<2 {
      for frame in 0..<960 { stereoSamples.floatChannelData![channel][frame] = 0.25 }
    }
    let mono = try downmix.convert(stereoSamples)!
    precondition(mono.format == target && mono.frameLength > 0)
    precondition(abs(mono.floatChannelData![0][10] - 0.25) < 0.01)

    // Tap timing keeps only durations, bounded, with ordered percentiles.
    var timing = AudioTapTiming()
    for value in 1...100 { timing.record(microseconds: Double(value)) }
    guard let summary = timing.summary else { preconditionFailure("timing summary missing") }
    precondition(summary.samples == 100 && summary.maximumMicroseconds == 100)
    precondition(summary.p50Microseconds <= summary.p95Microseconds &&
      summary.p95Microseconds <= summary.p99Microseconds &&
      summary.p99Microseconds <= summary.maximumMicroseconds)
    for _ in 0..<10_000 { timing.record(microseconds: 1) }
    precondition(timing.summary?.samples == 10_100)

    // Passthrough conversion copies: changing the input later cannot mutate the
    // buffer already handed to the recording sink.
    guard let passthrough = LiveAudioBufferConverter(source: source, target: source) else {
      preconditionFailure("passthrough conversion unavailable")
    }
    let first = try passthrough.convert(input)!
    let saved = first.floatChannelData![0][10]
    input.floatChannelData![0][10] = 0.9
    precondition(first.floatChannelData![0][10] == saved)
    precondition(first !== input)

    print("RecordingMicrophoneInputChecks: passed (44.1 kHz mono target, gap/duplicate/empty clock verdicts, 48 kHz and stereo conversion, owned passthrough copy; AVAudioEngine tap start/stop needs a device)")
  }
}
