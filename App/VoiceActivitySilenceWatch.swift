import AVFoundation
import FluidAudio
import Foundation
import Synchronization

/// Receives a bounded copy from the microphone tap and analyzes it off the
/// recording path. The duration of a quiet run is independent of the queue.
actor VoiceActivitySilenceWatch {
  private static let speechThreshold: Float = 0.3
  private static let quietSampleCount = 90 * VadManager.sampleRate
  private static let framesPerStep = 4_096

  private var detector: VadManager?
  private var state = VadStreamState.initial()
  private var pending: [Float] = []
  private var quietSamples = 0
  private var generation: Int?
  private var isEvaluating = false
  private nonisolated let queue = Mutex(Queue())

  nonisolated func setEnabled(_ enabled: Bool) {
    queue.withLock { value in
      guard value.enabled != enabled else { return }
      value.enabled = enabled
      value.reset()
    }
  }

  nonisolated func submit(_ buffer: AVAudioPCMBuffer) {
    guard buffer.frameLength > 0, !buffer.format.isInterleaved,
          let channels = buffer.floatChannelData else { return }
    let count = Int(buffer.frameLength)
    let rate = buffer.format.sampleRate
    let channelCount = Int(buffer.format.channelCount)
    guard rate.isFinite, rate > 0, channelCount > 0 else { return }
    queue.withLock { value in
      guard value.enabled else { return }
      let limit = Int(8 * rate)
      // A dropped interval or a changed microphone format breaks continuity.
      if value.rate != rate || value.samples.count + count > limit { value.reset() }
      value.rate = rate
      let start = max(0, count - limit)
      if channelCount == 1 {
        value.samples.append(contentsOf: UnsafeBufferPointer(start: channels[0] + start, count: count - start))
      } else {
        for index in start..<count {
          var peak: Float = 0
          for channel in 0..<channelCount {
            let sample = channels[channel][index]
            if abs(sample) > abs(peak) { peak = sample }
          }
          value.samples.append(peak)
        }
      }
    }
  }

  func evaluate() async -> Bool? {
    guard !isEvaluating else { return nil }
    isEvaluating = true
    defer { isEvaluating = false }
    if detector == nil {
      guard let model = await VoiceActivityModelAssets.shared.model() else { return nil }
      detector = VadManager(config: VadConfig(defaultThreshold: Self.speechThreshold), vadModel: model)
    }
    guard !Task.isCancelled, let detector else { return nil }
    let input = queue.withLock { value in
      let input = value
      value.samples.removeAll(keepingCapacity: true)
      return input
    }
    guard input.enabled, !input.samples.isEmpty else { return nil }
    if generation != input.generation {
      resetAnalysis()
      generation = input.generation
    }
    guard let converted = Self.resample(input.samples, from: input.rate) else {
      resetAnalysis()
      return false
    }
    pending.append(contentsOf: converted)
    var offset = 0
    let step = Self.framesPerStep
    while pending.count - offset >= step {
      let chunk = Array(pending[offset..<(offset + step)])
      guard let result = try? await detector.processStreamingChunk(chunk, state: state),
            result.probability.isFinite else {
        resetAnalysis()
        return false
      }
      guard !Task.isCancelled, queue.withLock({ $0.generation == input.generation }) else {
        resetAnalysis()
        return nil
      }
      state = result.state
      quietSamples = result.probability >= Self.speechThreshold ? 0
        : min(Self.quietSampleCount, quietSamples + step)
      offset += step
    }
    pending.removeFirst(offset)
    return quietSamples >= Self.quietSampleCount
  }

  private func resetAnalysis() {
    state = VadStreamState.initial()
    quietSamples = 0
    pending.removeAll(keepingCapacity: true)
  }

  private static func resample(_ samples: [Float], from rate: Double) -> [Float]? {
    let targetRate = Double(VadManager.sampleRate)
    if rate == targetRate { return samples }
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let target = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1),
          let converter = AVAudioConverter(from: format, to: target) else { return nil }
    let capacity = AVAudioFrameCount((Double(samples.count) * targetRate / rate).rounded(.up)) + 64
    guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
          let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity),
          let source = input.floatChannelData?[0] else { return nil }
    input.frameLength = AVAudioFrameCount(samples.count)
    source.update(from: samples, count: samples.count)
    var supplied = false
    var failure: NSError?
    let status = converter.convert(to: output, error: &failure) { _, inputStatus in
      if supplied {
        inputStatus.pointee = .endOfStream
        return nil
      }
      supplied = true
      inputStatus.pointee = .haveData
      return input
    }
    guard failure == nil, status != .error, output.frameLength > 0,
          let values = output.floatChannelData?[0] else { return nil }
    return Array(UnsafeBufferPointer(start: values, count: Int(output.frameLength)))
  }

  private struct Queue: Sendable {
    var enabled = false
    var generation = 0
    var samples: [Float] = []
    var rate: Double = 0

    mutating func reset() {
      generation += 1
      samples.removeAll(keepingCapacity: enabled)
    }
  }
}
