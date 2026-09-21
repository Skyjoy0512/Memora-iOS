import AVFAudio
import Foundation
import MediaPlayer

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
    didSet {
      timePitch.rate = rate
      publishNowPlaying()
    }
  }
  /// The name shown in the system now-playing controls, set from the record.
  private var nowPlayingTitle = ""

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
  func load(_ url: URL?, title: String = "") {
    guard loadedURL != url else { return }
    stop()
    loadedURL = url
    nowPlayingTitle = title
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
      registerRemoteCommands()

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
      publishNowPlaying()
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
    publishNowPlaying()
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
    publishNowPlaying()
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
    // Nothing is playing any more, so the system should not keep a now-playing
    // item that looks like it still is.
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.removeTarget(nil)
    commands.pauseCommand.removeTarget(nil)
    commands.togglePlayPauseCommand.removeTarget(nil)
    commands.changePlaybackPositionCommand.removeTarget(nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  /// Publishes what is actually playing - the record own name, no invented
  /// artist - so Control Center and the lock screen match the screen.
  private func publishNowPlaying() {
    guard file != nil, isPlaying || currentTime > 0 else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: nowPlayingTitle.isEmpty ? "無題の記録" : nowPlayingTitle,
      MPMediaItemPropertyArtist: "Memora",
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
    ]
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// Lets the lock screen and Control Center drive this player, so their
  /// buttons never claim to work while doing nothing.
  private func registerRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.play() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.toggle() }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      Task { @MainActor in self?.seek(to: position.positionTime) }
      return .success
    }
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
