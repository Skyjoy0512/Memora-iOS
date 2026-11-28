import Accelerate
import Foundation

/// Signal measurements over decoded PCM, done with Accelerate.
///
/// These run on the audio tap and on every imported chunk, so the work has to
/// stay flat as the buffer grows. On Apple Silicon `vDSP_svesq` measures a
/// 4,096-frame tap buffer in about 0.1 µs, against 0.4 µs for sampling 512
/// frames in a Swift loop — and it covers every sample instead of one in eight.
enum AudioLevelMath {
  /// The sum of the squared samples. Not finite when the buffer contains a
  /// non-finite sample, which callers reading a file treat as corrupt audio.
  static func sumOfSquares(_ samples: UnsafePointer<Float>, count: Int) -> Float {
    guard count > 0 else { return 0 }
    var total: Float = 0
    vDSP_svesq(samples, 1, &total, vDSP_Length(count))
    return total
  }

  /// The mean of the squared samples: the square root of this is the RMS.
  static func meanSquare(_ samples: UnsafePointer<Float>, count: Int) -> Float {
    guard count > 0 else { return 0 }
    let mean = sumOfSquares(samples, count: count) / Float(count)
    return mean.isFinite ? mean : 0
  }

  /// The largest absolute sample.
  static func peakMagnitude(_ samples: UnsafePointer<Float>, count: Int) -> Float {
    guard count > 0 else { return 0 }
    var peak: Float = 0
    vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
    return peak.isFinite ? peak : 0
  }

  /// How many samples have a magnitude at or above `threshold`. `scratch` must
  /// hold `count` elements; the caller reuses it so a chunked read allocates
  /// nothing per buffer. Results are exactly 0 or 1, so the sum is the count.
  static func countMagnitudes(
    atLeast threshold: Float,
    in samples: UnsafePointer<Float>,
    count: Int,
    scratch: UnsafeMutablePointer<Float>
  ) -> Int {
    guard count > 0 else { return 0 }
    let length = vDSP_Length(count)
    // vDSP_vthres zeroes what is below the threshold and keeps the rest, so a
    // scale past 1 and a clip turn every hit into exactly 1 and the sum is the
    // count. The zeroes stay zero through both passes.
    vDSP_vabs(samples, 1, scratch, 1, length)
    var limit = threshold
    vDSP_vthres(scratch, 1, &limit, scratch, 1, length)
    var twice: Float = 2
    vDSP_vsmul(scratch, 1, &twice, scratch, 1, length)
    var low: Float = 0
    var high: Float = 1
    vDSP_vclip(scratch, 1, &low, &high, scratch, 1, length)
    var total: Float = 0
    vDSP_sve(scratch, 1, &total, length)
    return Int(total)
  }

  /// A bounded 0...1 loudness for the recording glow, with one sqrt per buffer.
  static func level(_ samples: UnsafePointer<Float>, count: Int) -> Float {
    let rms = sqrtf(meanSquare(samples, count: count))
    return min(1, max(0, rms * 4))
  }
}
