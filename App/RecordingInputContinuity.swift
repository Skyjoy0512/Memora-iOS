import AVFAudio
import Foundation

/// Watches the host sample clock across input-tap callbacks so a dropped or
/// repeated buffer is reported instead of being compressed into the recording
/// timeline. Some devices deliver buffers without a valid sample time; those
/// cannot be checked and are treated as continuous.
struct RecordingInputContinuity {
  enum Verdict: Equatable {
    case first
    case continuous
    case empty
    case gap
    case duplicate
    case unchecked
  }

  private var nextSampleTime: AVAudioFramePosition?

  mutating func observe(sampleTime: AVAudioFramePosition?, frames: AVAudioFrameCount) -> Verdict {
    guard frames > 0 else { return .empty }
    guard let sampleTime else {
      nextSampleTime = nil
      return .unchecked
    }
    defer { nextSampleTime = sampleTime + AVAudioFramePosition(frames) }
    guard let expected = nextSampleTime else { return .first }
    if sampleTime == expected { return .continuous }
    return sampleTime > expected ? .gap : .duplicate
  }

  mutating func reset() {
    nextSampleTime = nil
  }
}
