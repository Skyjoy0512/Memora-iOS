import Foundation
import CoreFoundation

/// Provider counts already include reasoning in output. Detail fields are
/// subsets, so adding them again would overstate usage.
struct CloudTokenUsage {
  var outputTokens: Int?

  init(response: [String: Any], usesAnthropicAPI: Bool) {
    let usage = response["usage"] as? [String: Any]
    let value = usage?[usesAnthropicAPI ? "output_tokens" : "completion_tokens"]
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          let count = Int(exactly: number.doubleValue), count >= 0 else {
      outputTokens = nil
      return
    }
    outputTokens = count
  }
}
