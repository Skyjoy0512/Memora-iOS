import Foundation

enum SpeakerEmbeddingMath {
  static func mean(_ vectors: [[Float]]) -> [Float]? {
    guard let dimension = vectors.first?.count, dimension > 0,
          vectors.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) }) else { return nil }
    var sum = [Double](repeating: 0, count: dimension)
    for vector in vectors {
      for index in vector.indices { sum[index] += Double(vector[index]) }
    }
    let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
    guard norm.isFinite, norm > 0 else { return nil }
    return sum.map { Float($0 / norm) }
  }

  static func cosine(_ left: [Float], _ right: [Float]) -> Double? {
    guard !left.isEmpty, left.count == right.count,
          left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite) else { return nil }
    var product = 0.0
    var leftNorm = 0.0
    var rightNorm = 0.0
    for index in left.indices {
      product += Double(left[index]) * Double(right[index])
      leftNorm += Double(left[index]) * Double(left[index])
      rightNorm += Double(right[index]) * Double(right[index])
    }
    guard leftNorm > 0, rightNorm > 0 else { return nil }
    return max(-1, min(1, product / sqrt(leftNorm * rightNorm)))
  }
}
