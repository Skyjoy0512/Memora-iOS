import FluidAudio
import Foundation

actor VoiceSampleAnalyzer {
  static let shared = VoiceSampleAnalyzer()

  func assess(_ url: URL, intervals: [SpeakerInterval]) throws -> VoiceQualityMetadata {
    let samples = try AudioConverter().resampleAudioFile(url)
    guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw SpeakerProcessingFailure.noSpeech }
    let clipped = samples.filter { abs($0) >= 1 }.count
    let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    guard energy > 0 else { throw SpeakerProcessingFailure.noSpeech }
    guard clipped == 0 else { throw SpeakerProcessingFailure.clippedAudio }
    let ordered = intervals.filter(\.isValid).sorted { $0.start < $1.start }
    var end = 0.0
    var duration = 0.0
    for interval in ordered {
      duration += max(0, interval.end - max(end, interval.start))
      end = max(end, interval.end)
    }
    guard duration >= OfflineDiarizerConfig.default.embedding.minSegmentDurationSeconds else {
      throw SpeakerProcessingFailure.noSpeech
    }
    let speakers = Set(ordered.map(\.speakerID))
    guard speakers.count == 1 else { throw SpeakerProcessingFailure.multipleSpeakers }
    return VoiceQualityMetadata(sampleDuration: Double(samples.count) / 16_000,
      speechDuration: duration, peak: samples.map { abs($0) }.max() ?? 0,
      rootMeanSquare: sqrt(energy / Double(samples.count)), clippedSampleCount: clipped,
      detectedSpeakerCount: speakers.count)
  }
}
