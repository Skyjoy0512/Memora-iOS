import AVFAudio
import Foundation
import Synchronization

/// The tap only meters and copies audio into the analyzer's bounded feeder.
final class LiveMicrophoneBridge: @unchecked Sendable {
  struct Snapshot: Sendable {
    var frames = 0
    var peak: Float = 0
    var voicedSeconds: Double = 0
  }

  private struct State {
    var feeder: LiveAudioInputFeeder?
    var snapshot = Snapshot()
  }

  private let state = Mutex(State())

  func replace(with feeder: LiveAudioInputFeeder?) {
    let previous = state.withLock {
      let previous = $0.feeder
      $0.feeder = feeder
      $0.snapshot = Snapshot()
      return previous
    }
    previous?.finish()
  }

  func consume(_ buffer: AVAudioPCMBuffer) {
    guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
    var sum: Float = 0
    if let samples = buffer.floatChannelData?[0] {
      for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
    }
    let rms = sqrt(sum / Float(buffer.frameLength))
    let feeder = state.withLock {
      $0.snapshot.frames += Int(buffer.frameLength)
      $0.snapshot.peak = max($0.snapshot.peak, rms)
      if rms > 0.01 { $0.snapshot.voicedSeconds += Double(buffer.frameLength) / buffer.format.sampleRate }
      return $0.feeder
    }
    feeder?.consume(buffer)
  }

  func snapshot() -> Snapshot {
    state.withLock {
      let snapshot = $0.snapshot
      $0.snapshot.peak = 0
      return snapshot
    }
  }
}
