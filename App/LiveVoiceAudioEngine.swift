import AVFAudio
import Foundation

// Adapted from Volocal's SharedAudioEngine (MIT). See Resources/Volocal-LICENSE.txt.
@MainActor
final class LiveVoiceAudioEngine {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var playbackRevision = UUID()
  private var queuedFrames = 0
  private var converter: AVAudioConverter?
  private var sourceRate: Double?
  private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

  var queuedSeconds: Double { Double(queuedFrames) / format.sampleRate }

  func start(bridge: LiveSpeechRequestBridge) throws {
    stop()
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try session.setActive(true)
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    // Full duplex only starts when echo cancellation is available.
    try engine.inputNode.setVoiceProcessingEnabled(true)
    try engine.outputNode.setVoiceProcessingEnabled(true)
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw LiveVoiceError.unavailable("利用できるマイクが見つかりません。")
    }
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.inputNode.installTap(onBus: 0, bufferSize: 2_048, format: nil) { buffer, _ in
      bridge.append(buffer)
    }
    self.engine = engine
    self.player = player
    engine.prepare()
    try engine.start()
    player.play()
  }

  func schedule(_ chunk: LiveAudioChunk) throws {
    guard let player, let engine, engine.isRunning else { throw LiveVoiceError.unavailable("音声の再生が中断されました。") }
    guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: chunk.sampleRate, channels: 1),
          let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(chunk.samples.count)) else {
      throw LiveVoiceError.unavailable("読み上げの音声形式を利用できません。")
    }
    input.frameLength = AVAudioFrameCount(chunk.samples.count)
    chunk.samples.withUnsafeBufferPointer { source in
      if let address = source.baseAddress { input.floatChannelData?[0].update(from: address, count: source.count) }
    }
    if sourceRate != chunk.sampleRate {
      converter = AVAudioConverter(from: sourceFormat, to: format)
      sourceRate = chunk.sampleRate
    }
    guard let converter,
          let output = AVAudioPCMBuffer(pcmFormat: format,
            frameCapacity: AVAudioFrameCount(ceil(Double(chunk.samples.count) * 24_000 / chunk.sampleRate) + 64)) else {
      throw LiveVoiceError.unavailable("読み上げの音声を変換できません。")
    }
    var supplied = false
    var conversionError: NSError?
    converter.convert(to: output, error: &conversionError) { _, status in
      guard !supplied else { status.pointee = .noDataNow; return nil }
      supplied = true
      status.pointee = .haveData
      return input
    }
    if let conversionError { throw conversionError }
    guard output.frameLength > 0 else { return }
    let frames = Int(output.frameLength)
    queuedFrames += frames
    let revision = playbackRevision
    player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.playbackRevision == revision else { return }
        self.queuedFrames = max(0, self.queuedFrames - frames)
      }
    }
  }

  func stopPlayback() {
    playbackRevision = UUID()
    queuedFrames = 0
    converter = nil
    sourceRate = nil
    player?.stop()
    if engine?.isRunning == true { player?.play() }
  }

  func stop() {
    stopPlayback()
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    player = nil
  }
}
