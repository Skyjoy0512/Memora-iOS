import Foundation

/// Compiled only by build-native.sh. The shipping app cannot select these routes.
enum NativeSummaryEvaluation {
  struct Options: Decodable, Sendable {
    var variant: String
    var concurrency: Int
    var partCapacity: Int?
    func accepts(parts: Int) -> Bool {
      if ["single-pass", "capacity-single-pass", "sot"].contains(variant) { return parts == 1 }
      return parts > 1
    }
  }
  @TaskLocal static var options: Options?
  static var configuration: URLSessionConfiguration {
    let value = URLSessionConfiguration.ephemeral
    value.protocolClasses = [NativeSummaryWire.self]
    return value
  }
}
