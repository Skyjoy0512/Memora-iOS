import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class AudioPlaybackService {
  var isPlaying = false
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 1

  @ObservationIgnored private let engine = AVAudioEngine()
  @ObservationIgnored private let node = AVAudioPlayerNode()
  @ObservationIgnored private var file: AVAudioFile?
  @ObservationIgnored private var audioURL: URL?
  @ObservationIgnored private var ticker: Task<Void, Never>?
  @ObservationIgnored private var playbackStartedAt: Date?
  @ObservationIgnored private var playbackStartPosition: TimeInterval = 0

  init() {
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: nil)
  }

  func configure(url: URL?, fallbackDuration: TimeInterval) {
    guard audioURL != url else { return }
    stop()
    audioURL = url
    duration = max(fallbackDuration, 1)
    guard let url else {
      file = nil
      return
    }
    if let file = try? AVAudioFile(forReading: url) {
      self.file = file
      duration = max(Double(file.length) / file.processingFormat.sampleRate, 1)
    }
  }

  func togglePlayback() {
    isPlaying ? pause() : play()
  }

  func seek(to fraction: Double) {
    let newTime = min(max(fraction, 0), 1) * duration
    currentTime = newTime
    playbackStartPosition = newTime
    playbackStartedAt = .now
    if isPlaying, file != nil {
      scheduleAudio(from: newTime)
    }
  }

  func stop() {
    ticker?.cancel()
    ticker = nil
    node.stop()
    engine.stop()
    isPlaying = false
    currentTime = 0
  }

  private func play() {
    if currentTime >= duration {
      currentTime = 0
      playbackStartPosition = 0
    }
    isPlaying = true
    playbackStartPosition = currentTime
    playbackStartedAt = .now
    if file != nil {
      scheduleAudio(from: currentTime)
    }
    startTicker()
  }

  private func pause() {
    node.pause()
    ticker?.cancel()
    ticker = nil
    isPlaying = false
    playbackStartPosition = currentTime
    playbackStartedAt = nil
  }

  private func scheduleAudio(from time: TimeInterval) {
    guard let file else { return }
    let sampleRate = file.processingFormat.sampleRate
    let startFrame = AVAudioFramePosition(time * sampleRate)
    let remainingFrames = max(file.length - startFrame, 0)
    guard remainingFrames > 0 else {
      finishPlayback()
      return
    }

    node.stop()
    node.scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: AVAudioFrameCount(remainingFrames),
      at: nil
    ) { [weak self] in
      Task { @MainActor in
        self?.finishPlayback()
      }
    }
    do {
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
      node.play()
    } catch {
      finishPlayback()
    }
  }

  private func startTicker() {
    ticker?.cancel()
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard let self,
              let playbackStartedAt = self.playbackStartedAt,
              self.isPlaying else { return }
        self.currentTime = min(
          self.playbackStartPosition + Date.now.timeIntervalSince(playbackStartedAt),
          self.duration
        )
        if self.currentTime >= self.duration {
          self.finishPlayback()
          return
        }
      }
    }
  }

  private func finishPlayback() {
    ticker?.cancel()
    ticker = nil
    node.stop()
    isPlaying = false
    currentTime = duration
    playbackStartPosition = currentTime
    playbackStartedAt = nil
  }
}
