import Foundation

struct AudioSignalReport: Codable, Sendable {
  var duration: TimeInterval
  var sampleRate: Double
  var channels: Int
  var codec: UInt32
  var rmsDBFS: Double
  var peak: Double
  var clippedSampleFraction: Double
  /// An energy measurement, not a speech/silence classification.
  var quietFrameFraction: Double
  var inspectedFrames: Int64

  var isValid: Bool {
    duration.isFinite && duration > 0 && sampleRate.isFinite && sampleRate > 0 &&
      (1...32).contains(channels) && rmsDBFS.isFinite && peak.isFinite && peak >= 0 &&
      clippedSampleFraction.isFinite && (0...1).contains(clippedSampleFraction) &&
      quietFrameFraction.isFinite && (0...1).contains(quietFrameFraction) && inspectedFrames > 0
  }
}
