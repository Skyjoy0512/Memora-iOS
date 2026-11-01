import AVFAudio
import AVFoundation
import Observation

@MainActor @Observable
final class SourceVideoPlayback {
  private(set) var player: AVPlayer?
  private(set) var notice: String?
  @ObservationIgnored private var token: AudioSessionCoordinator.Token?
  @ObservationIgnored private var stopper: UUID?
  @ObservationIgnored private var pauser: UUID?

  func load(_ url: URL, start: TimeInterval?) async {
    stop()
    guard !Task.isCancelled else { return }
    let coordinator = AudioSessionCoordinator.shared
    guard let claim = coordinator.claim(.playback) else {
      notice = coordinator.refusal(for: .playback)
      return
    }
    token = claim
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
      let loaded = AVPlayer(url: url)
      player = loaded
      notice = nil
      stopper = coordinator.registerStopper(.playback) { [weak self] in self?.stop() }
      pauser = coordinator.registerPlaybackPauser { [weak self] in self?.stop() }
      if let time = ProjectCitationLocation.playbackTime(start) {
        await loaded.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        guard !Task.isCancelled, coordinator.owns(claim), player === loaded else { return }
        loaded.play()
      }
    } catch {
      stop()
      notice = "再生できませんでした。もう一度お試しください。"
    }
  }

  func stop() {
    player?.pause()
    player = nil
    let coordinator = AudioSessionCoordinator.shared
    if let stopper { coordinator.unregisterStopper(stopper, for: .playback) }
    if let pauser { coordinator.unregisterPlaybackPauser(pauser) }
    stopper = nil; pauser = nil
    if let token { coordinator.release(token) }
    token = nil
  }
}
