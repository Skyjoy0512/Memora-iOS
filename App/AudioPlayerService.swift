import AVFAudio
import Foundation
import MediaPlayer

/// Plays original files on one frame timeline without creating a combined file.
@MainActor
@Observable
final class AudioPlayerService {
  private(set) var isPlaying = false
  private(set) var currentTime: TimeInterval = 0
  private(set) var duration: TimeInterval = 0
  /// Shown when the file could not be opened.
  private(set) var errorMessage: String?
  /// Playback speed, kept across recordings and app launches.
  var rate: Float = AudioPlayerService.storedRate() {
    didSet {
      timePitch.rate = rate
      UserDefaults.standard.set(rate, forKey: Self.rateKey)
      publishNowPlaying()
    }
  }

  private static let rateKey = "memora.playbackRate"

  /// The speed this device last chose, so a new recording opens at the same one.
  private static func storedRate() -> Float {
    let stored = UserDefaults.standard.float(forKey: rateKey)
    return stored == 0 ? 1 : stored
  }
  /// The name shown in the system now-playing controls, set from the record.
  private var nowPlayingTitle = ""

  /// Built on the first play, not when the screen opens: setting up the
  /// engine's output takes the audio session, which would stop the music
  /// someone is listening to just by opening a record.
  private var engine: AVAudioEngine?
  /// The file format the graph is wired for, so it is only rewired on change.
  private var connectedFormat: AVAudioFormat?
  private let player = AVAudioPlayerNode()
  private let timePitch = AVAudioUnitTimePitch()
  private var source: AudioPlaybackSource?
  private var startFrame: AVAudioFramePosition = 0
  private var playbackSchedule = AudioPlaybackSchedule()
  private var scheduledFiles: [Int64: AVAudioFile] = [:]
  private var ticker: Task<Void, Never>?
  private var loadedInput: AudioPlaybackInput?
  /// The session claim this player holds, so only this run gives it up.
  private var sessionToken: AudioSessionCoordinator.Token?
  /// The coordinator's handle for pausing this player when another takes over.
  private var playbackPauserID: UUID?
  /// The remote-command targets this player registered, so it removes only its
  /// own and never duplicates them on repeated plays.
  private var remoteCommandTargets: [(command: MPRemoteCommand, token: Any)] = []

  init() {
    timePitch.rate = rate
    // A stale handler only holds a weak player, so it does nothing once this one
    // is gone; it is registered once here rather than on every play.
    AudioSessionCoordinator.shared.registerStopper(.playback) { [weak self] in
      self?.stop()
    }
  }

  private var sampleRate: Double {
    source?.sampleRate ?? 44_100
  }

  /// Points the player at a recording. Loading the same file again does nothing,
  /// so scrolling the screen does not restart it.
  func load(_ url: URL?, title: String = "") {
    load(input: url.map { .file($0) }, title: title)
  }

  func load(input: AudioPlaybackInput?, title: String = "") {
    nowPlayingTitle = title
    guard loadedInput != input || errorMessage != nil else { return }
    stop()
    source = nil
    loadedInput = input
    errorMessage = nil
    guard let input else {
      duration = 0
      return
    }

    do {
      let source = try AudioPlaybackSource(input)
      self.source = source
      duration = Double(source.length) / source.sampleRate
    } catch {
      duration = 0
      errorMessage = "音声を読み込めませんでした。ファイルが残っているか確認してください。"
    }
  }

  func toggle() {
    isPlaying ? pause() : play()
  }

  func play() {
    guard let source, !isPlaying else { return }
    guard let token = AudioSessionCoordinator.shared.claim(.playback) else {
      errorMessage = AudioSessionCoordinator.shared.refusal(for: .playback)
        ?? "今は再生できません。"
      return
    }
    sessionToken = token

    if startFrame >= source.length {
      startFrame = 0
      currentTime = 0
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)
      registerRemoteCommands()

      let engine = preparedEngine(for: source.format)
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }

      let segments = playbackSchedule.start(
        at: startFrame, length: source.length, sampleRate: sampleRate, partEnds: source.partEnds
      )
      guard !segments.isEmpty else {
        throw CocoaError(.fileReadCorruptFile)
      }
      for segment in segments { try enqueue(segment) }
      player.play()
      errorMessage = nil
      isPlaying = true
      publishNowPlaying()
      startTicker()
      if playbackPauserID == nil {
        playbackPauserID = AudioSessionCoordinator.shared.registerPlaybackPauser { [weak self] in
          self?.pause()
        }
      }
    } catch {
      failPlayback()
    }
  }

  private func enqueue(_ segment: AudioPlaybackSchedule.Segment) throws {
    guard let source else { throw CocoaError(.fileReadCorruptFile) }
    let resolved = try source.resolve(segment)
    scheduledFiles[segment.start] = resolved.file
    player.scheduleSegment(
      resolved.file, startingFrame: resolved.start, frameCount: segment.count, at: nil,
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isPlaying, self.playbackSchedule.contains(segment) else { return }
        self.scheduledFiles[segment.start] = nil
        guard let next = self.playbackSchedule.complete(segment) else { return }
        do { try self.enqueue(next) }
        catch { self.failPlayback() }
      }
    }
  }

  private func failPlayback() {
    let elapsed = isPlaying ? elapsedTime() : currentTime
    stop()
    startFrame = frame(for: elapsed)
    currentTime = Double(startFrame) / sampleRate
    errorMessage = "再生を開始できませんでした。"
  }

  /// Wires the graph for the file's format, which has to match before
  /// scheduling. Only called once the session is ours.
  private func preparedEngine(for format: AVAudioFormat) -> AVAudioEngine {
    let engine: AVAudioEngine
    if let existing = self.engine {
      engine = existing
    } else {
      engine = AVAudioEngine()
      engine.attach(player)
      engine.attach(timePitch)
      self.engine = engine
    }
    if connectedFormat != format {
      engine.connect(player, to: timePitch, format: format)
      engine.connect(timePitch, to: engine.mainMixerNode, format: format)
      connectedFormat = format
    }
    return engine
  }

  func pause() {
    guard isPlaying else { return }
    let elapsed = elapsedTime()
    playbackSchedule.cancel()
    player.stop()
    player.reset()
    scheduledFiles.removeAll(keepingCapacity: true)
    startFrame = frame(for: elapsed)
    currentTime = min(elapsed, duration)
    isPlaying = false
    publishNowPlaying()
    stopTicker()
  }

  func seek(to time: TimeInterval) {
    let targetFrame = frame(for: time)
    let clamped = Double(targetFrame) / sampleRate
    let wasPlaying = isPlaying
    playbackSchedule.cancel()
    if wasPlaying {
      player.stop()
      player.reset()
    }
    scheduledFiles.removeAll(keepingCapacity: true)
    startFrame = targetFrame
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
    playbackSchedule.cancel()
    if engine != nil {
      player.stop()
      player.reset()
    }
    scheduledFiles.removeAll(keepingCapacity: true)
    isPlaying = false
    currentTime = 0
    startFrame = 0
    // A running engine keeps the output open; stopping it lets the music the
    // session hands back play on.
    engine?.stop()
    // Nothing is playing any more, so the system should not keep a now-playing
    // item that looks like it still is.
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if let playbackPauserID {
      AudioSessionCoordinator.shared.unregisterPlaybackPauser(playbackPauserID)
      self.playbackPauserID = nil
    }
    removeRemoteCommands()
    // Gives the session back only for this player's own claim, so leaving a
    // screen cannot silence a recording or a newer playback.
    if let sessionToken {
      AudioSessionCoordinator.shared.release(sessionToken)
      self.sessionToken = nil
    }
  }

  /// Publishes what is actually playing - the record own name, no invented
  /// artist - so Control Center and the lock screen match the screen.
  private func publishNowPlaying() {
    guard source != nil, isPlaying || currentTime > 0 else {
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
  /// buttons never claim to work while doing nothing. The targets are added once
  /// per playback and remembered, so repeated plays do not stack duplicates and
  /// stopping removes only this player's own.
  private func registerRemoteCommands() {
    guard remoteCommandTargets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    remoteCommandTargets = [
      (center.playCommand, center.playCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.play() }
        return .success
      }),
      (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.pause() }
        return .success
      }),
      (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
        Task { @MainActor in self?.toggle() }
        return .success
      }),
      (center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
        guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
        Task { @MainActor in self?.seek(to: position.positionTime) }
        return .success
      })
    ]
  }

  /// Removes only the targets this player added.
  private func removeRemoteCommands() {
    for entry in remoteCommandTargets {
      entry.command.removeTarget(entry.token)
    }
    remoteCommandTargets = []
  }

  private func elapsedTime() -> TimeInterval {
    guard source != nil else { return 0 }
    let offset = Double(startFrame) / sampleRate
    guard let nodeTime = player.lastRenderTime,
          let playerTime = player.playerTime(forNodeTime: nodeTime) else {
      return offset
    }
    return offset + Double(playerTime.sampleTime) / sampleRate
  }

  private func frame(for time: TimeInterval) -> AVAudioFramePosition {
    AudioPlaybackSchedule.frame(at: time, length: source?.length ?? 0, sampleRate: sampleRate)
  }

  private func startTicker() {
    stopTicker()
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let self, self.isPlaying else { return }
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
