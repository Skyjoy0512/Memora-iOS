import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Evaluation adapter for the bundled, locally verified Silero model.
///
/// It downloads nothing and uploads nothing. It reads a file and reports
/// where speech was; removing the silence is `VoiceActivityTrim`'s work,
/// and the stored recording is never replaced by what it produces.
actor FluidVoiceActivityEvaluator {
  private let detector: VadManager

  init(model: MLModel) {
    detector = VadManager(config: VadConfig(defaultThreshold: 0.3), vadModel: model)
  }

  func evaluate(_ url: URL) async throws -> VoiceActivityTimeline {
    try await AudioProcessingDiagnostics.trace(.voiceActivity) { try await perform(url) } outcome: { _ in .success }
  }

  private func perform(_ url: URL) async throws -> VoiceActivityTimeline {
    let diagnostic = AudioProcessingDiagnostics.current
    diagnostic?.setEngine(.silero)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let file = try AVAudioFile(forReading: url)
    let source = file.processingFormat
    let duration = Double(file.length) / source.sampleRate
    diagnostic?.setAudioSeconds(duration)
    let span = diagnostic?.begin(.vad, audioSeconds: duration)
    var outcome: AudioDiagnosticReport.Outcome = .failed
    defer { diagnostic?.end(span, outcome: Task.isCancelled ? .cancelled : outcome) }
    guard duration.isFinite, duration > 0, duration <= SourceMediaChunk.durationPerChunk + 1,
          let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
          let converter = AVAudioConverter(from: source, to: target),
          let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4_096),
          let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 8_192) else {
      throw SourceMediaFailure.invalidTemporaryFile
    }
    var state = await detector.makeStreamState()
    var probabilities: [Float] = []
    while true {
      try Task.checkCancellation()
      var readFailure: Error?
      var conversionFailure: NSError?
      let status = converter.convert(to: output, error: &conversionFailure) { requested, inputStatus in
        do {
          if file.framePosition >= file.length { inputStatus.pointee = .endOfStream; return nil }
          try file.read(into: input, frameCount: min(requested, input.frameCapacity))
          inputStatus.pointee = .haveData
          return input
        } catch {
          readFailure = error
          inputStatus.pointee = .endOfStream
          return nil
        }
      }
      if let readFailure { throw readFailure }
      if let conversionFailure { throw conversionFailure }
      guard status != .error else { throw SourceMediaFailure.invalidTemporaryFile }
      if output.frameLength > 0 {
        guard let samples = output.floatChannelData?[0] else { throw SourceMediaFailure.invalidTemporaryFile }
        let result = try await detector.processStreamingChunk(
          Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength))), state: state)
        state = result.state
        probabilities.append(result.probability)
      }
      if status == .endOfStream { break }
      guard output.frameLength > 0 else { throw SourceMediaFailure.invalidTemporaryFile }
    }
    let timeline = try VoiceActivityTimeline.candidates(probabilities: probabilities, frameDuration: 0.256, duration: duration)
    outcome = .success
    return timeline
  }
}
