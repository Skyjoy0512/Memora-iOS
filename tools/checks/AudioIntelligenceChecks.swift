import AVFoundation
import Foundation

@main struct AudioIntelligenceChecks {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try AudioProcessingReadiness.check(thermalState: .nominal)
    try AudioProcessingReadiness.check(thermalState: .fair)
    for state: ProcessInfo.ThermalState in [.serious, .critical] {
      do {
        try AudioProcessingReadiness.check(thermalState: state)
        preconditionFailure("Thermal pressure accepted")
      } catch SourceMediaFailure.thermalDeferred { }
    }
    let url = root.appendingPathComponent("stereo.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
      buffer.frameLength = 16_000
      for frame in 0..<16_000 {
        buffer.floatChannelData![0][frame] = frame < 8_000 ? 1 : 0
        buffer.floatChannelData![1][frame] = frame < 8_000 ? -1 : 0
      }
      try file.write(from: buffer)
    }
    let report = try AudioSignalInspector.inspect(url)
    precondition(report.channels == 2 && report.sampleRate == 16_000 && report.duration == 1)
    precondition(report.peak == 1 && report.clippedSampleFraction == 0.5 && report.quietFrameFraction == 0.5)
    precondition(abs(report.rmsDBFS - -3.0103) < 0.001)
    let candidates = try VoiceActivityTimeline.candidates(
      probabilities: [0.5] + Array(repeating: 0, count: 80) + [0.02], frameDuration: 0.256, duration: 82 * 0.256)
    precondition(candidates.ranges.count == 2)
    precondition(candidates.ranges[0].start == 0)
    let boundary = candidates.ranges[0].duration
    precondition(candidates.originalTime(for: boundary) == candidates.ranges[1].start)
    precondition(candidates.originalTime(for: -1) == nil)
    precondition(candidates.originalTime(for: .nan) == nil)
    for probabilities: [Float] in [[], [.nan], [0], [0.1]] {
      let conservative = try VoiceActivityTimeline.candidates(probabilities: probabilities,
        frameDuration: 0.256, duration: 10)
      precondition(conservative.ranges.count == 1 && conservative.ranges[0].duration == 10)
    }
    let short = try VoiceActivityTimeline.candidates(probabilities: [0.02], frameDuration: 0.256, duration: 0.1)
    precondition(short.ranges.first?.duration == 0.1)
    let day = try SourceMediaChunk.plan(duration: 86_400)
    precondition(day.count == 96)
    for (index, chunk) in day.enumerated() {
      precondition(chunk.start == Double(index) * 900 && chunk.duration == 900)
    }
    print("AudioIntelligenceChecks: PASS. Real stereo PCM metrics without antiphase downmix loss; low-probability and short-word retention; uncertain VAD fallback; discontinuous source-time mapping; 96 contiguous windows for 24h. No recognition quality, learned VAD or iPhone power claim.")
  }
}
