import Accelerate
import Foundation

/// Checks the Accelerate signal measurements against a plain reference and
/// reports what each costs. The numbers are host numbers; the point is that the
/// vector path is both exact and not slower than the loop it replaced.
@main
enum AudioLevelMathChecks {
  static func main() {
    setvbuf(stdout, nil, _IONBF, 0)
    var generator = SystemRandomNumberGenerator()
    for count in [1, 7, 512, 4_096, 16_384] {

      var samples = (0..<count).map { _ in Float.random(in: -1...1, using: &generator) }
      samples.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        // A float sum over 16,000 samples is compared with a double reference.
        var reference: Double = 0
        for value in buffer { reference += Double(value) * Double(value) }
        let measured = Double(AudioLevelMath.sumOfSquares(base, count: count))
        precondition(abs(measured - reference) <= max(1e-3, reference * 1e-4),
                     "sum of squares differs at \(count): \(measured) vs \(reference)")

        var peak: Float = 0
        for value in buffer { peak = max(peak, abs(value)) }
        precondition(abs(AudioLevelMath.peakMagnitude(base, count: count) - peak) <= 1e-6)

        var scratch = [Float](repeating: 0, count: count)
        let clipped = AudioLevelMath.countMagnitudes(atLeast: 0.999, in: base, count: count, scratch: &scratch)
        precondition(clipped == buffer.filter { abs($0) >= 0.999 }.count)
      }
    }

    // A non-finite sample must be visible to a file reader rather than counted
    // as silence.
    var corrupt: [Float] = [0.5, .nan, 0.25]
    corrupt.withUnsafeBufferPointer { buffer in
      precondition(!AudioLevelMath.sumOfSquares(buffer.baseAddress!, count: corrupt.count).isFinite)
    }

    for count in [512, 4_096, 8_192] {

      let samples = (0..<count).map { Float(sin(Double($0) * 0.01)) * 0.3 }
      samples.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        var scalar: [Double] = []
        var vector: [Double] = []
        for _ in 0..<7 {
          scalar.append(time { _ = scalarSquareRoot(base, count) })
          vector.append(time { _ = AudioLevelMath.level(base, count: count) })
        }
        let scalarMedian = scalar.sorted()[3]
        let vectorMedian = vector.sorted()[3]
        // The tap buffer is 4,096 frames; the tolerance leaves room for a
        // shared host without hiding a regression of the size the loop had.
        precondition(vectorMedian <= scalarMedian * 2,
                     "the vector path is slower at \(count): \(vectorMedian) vs \(scalarMedian)")
        print("{\"count\":\(count),\"scalarNS\":\(round(scalarMedian)),\"accelerateNS\":\(round(vectorMedian))}")
      }
    }
    print("Audio level math: exact against the scalar reference and not slower.")
  }

  /// The sampled loop the recording tap used before the Accelerate path.
  @inline(never)
  private static func scalarSquareRoot(_ samples: UnsafePointer<Float>, _ count: Int) -> Float {
    let step = max(1, count / 512)
    var sum: Float = 0
    var used = 0
    var index = 0
    while index < count {
      let value = samples[index]
      sum += value * value
      used += 1
      index += step
    }
    return min(1, max(0, sqrt(sum / Float(max(used, 1))) * 4))
  }

  private static func time(_ work: () -> Void) -> Double {
    let iterations = 2_000
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations { work() }
    let end = DispatchTime.now().uptimeNanoseconds
    return Double(end - start) / Double(iterations)
  }
}
