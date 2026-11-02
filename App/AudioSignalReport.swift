import Foundation

struct AudioSignalReport: Sendable {
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
}
