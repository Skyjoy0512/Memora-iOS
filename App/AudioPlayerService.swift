import AVFAudio
import Foundation

/// Plays one recording with `AVAudioEngine`, the way the app stores it: a file
/// on disk. Supports pause, seeking, skipping, and a speed change.
@MainActor
@Observable
final class AudioPlayerService {
  private(set) var isPlaying = false
  private(set) var currentTime: TimeInterval = 0
  private(set) var duration: TimeInterval = 0
  /// Shown when the file could not be opened.
  private(set) var errorMessage: String?
  /// Playback speed, kept across recordings.
  var rate: Float = 1 {
    didSet { timePitch.rate = rate }
  }

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let timePitch = AVAudioUnitTimePitch()
  private var file: AVAudioFile?
  private var startFrame: AVAudioFramePosition = 0
  private var ticker: Task<Void, Never>?
  private var loadedURL: URL?

  init() {
    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: nil)
    engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    timePitch.rate = rate
  }

  private var sampleRate: Double {
    file?.processingFormat.sampleRate ?? 44_100
  }

  /// Points the player at a recording. Loading the same file again does nothing,
  /// so scrolling the screen does not restart it.
  func load(_ url: URL?) {
    guard loadedURL != url else { return }
    stop()
    loadedURL = url
    errorMessage = nil
    guard let url else {
      file = nil
      duration = 0
      return
    }

    do {
      let file = try AVAudioFile(forReading: url)
      self.file = file
      duration = Double(file.length) / file.processingFormat.sampleRate

      // The connection has to match the file's format before scheduling.
      engine.connect(player, to: timePitch, format: file.processingFormat)
      engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    } catch {
      file = nil
      duration = 0
      errorMessage = "音声を読み込めませんでした。ファイルが残っているか確認してください。"
    }
  }

  func toggle() {
    isPlaying ? pause() : play()
  }

  func play() {
    guard let file, !isPlaying else { return }

    if startFrame >= file.length {
      startFrame = 0
      currentTime = 0
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)

      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }

      player.scheduleSegment(
        file,
        startingFrame: startFrame,
        frameCount: AVAudioFrameCount(file.length - startFrame),
        at: nil
      )
      player.play()
      isPlaying = true
      startTicker()
    } catch {
      errorMessage = "再生を開始できませんでした。"
    }
  }

  func pause() {
    guard isPlaying else { return }
    let elapsed = elapsedTime()
    player.stop()
    player.reset()
    startFrame = frame(for: elapsed)
    currentTime = min(elapsed, duration)
    isPlaying = false
    stopTicker()
  }

  func seek(to time: TimeInterval) {
    let clamped = min(max(0, time), duration)
    let wasPlaying = isPlaying
    if wasPlaying {
      player.stop()
      player.reset()
    }
    startFrame = frame(for: clamped)
    currentTime = clamped
    if wasPlaying {
      isPlaying = false
      play()
    }
  }

  func skip(by delta: TimeInterval) {
    seek(to: currentTime + delta)
  }

  /// Stops and unloads, e.g. when leaving the screen.
  func stop() {
    stopTicker()
    if isPlaying {
      player.stop()
      player.reset()
    }
    isPlaying = false
    currentTime = 0
    startFrame = 0
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func elapsedTime() -> TimeInterval {
    guard let file else { return 0 }
    let offset = Double(startFrame) / file.processingFormat.sampleRate
    guard let nodeTime = player.lastRenderTime,
          let playerTime = player.playerTime(forNodeTime: nodeTime) else {
      return offset
    }
    return offset + Double(playerTime.sampleTime) / file.processingFormat.sampleRate
  }

  private func frame(for time: TimeInterval) -> AVAudioFramePosition {
    max(0, AVAudioFramePosition(time * sampleRate))
  }

  private func startTicker() {
    stopTicker()
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard let self, self.isPlaying else { return }
        let elapsed = self.elapsedTime()
        self.currentTime = min(elapsed, self.duration)
        if self.currentTime >= self.duration - 0.05 {
          self.pause()
          self.seek(to: 0)
          return
        }
      }
    }
  }

  private func stopTicker() {
    ticker?.cancel()
    ticker = nil
  }
}
