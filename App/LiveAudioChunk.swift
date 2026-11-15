import AVFAudio

struct LiveAudioChunk: Sendable {
  var samples: [Float]
  var sampleRate: Double

  init?(buffer: AVAudioPCMBuffer) {
    let count = Int(buffer.frameLength)
    guard count > 0, count <= 1_000_000, buffer.format.channelCount > 0 else { return nil }
    sampleRate = buffer.format.sampleRate
    guard sampleRate.isFinite, sampleRate > 0 else { return nil }
    if let source = buffer.floatChannelData?[0] {
      samples = Array(UnsafeBufferPointer(start: source, count: count))
    } else if let source = buffer.int16ChannelData?[0] {
      samples = UnsafeBufferPointer(start: source, count: count).map { Float($0) / 32_768 }
    } else { return nil }
  }
}
