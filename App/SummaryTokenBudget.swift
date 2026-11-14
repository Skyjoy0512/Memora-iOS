import Foundation

/// UTF-8 byte fallback deliberately overestimates ordinary byte-tokenizer
/// input. It is a planning bound, never a provider token count or billable usage.
struct SummaryTokenBudget {
  var contextTokens: Int
  var sourceCapacity: Int
  var usesReviewedContext: Bool

  init?(capabilities: ModelCapabilities, outputReservation: Int, instructionText: String) {
    let context = capabilities.contextWindowTokens
    guard context > 0, context <= 16_000_000, outputReservation > 0 else { return nil }
    let framingAndSafety = max(2_048, context / 10)
    let capacity = context - Self.upperBound(instructionText) - outputReservation - framingAndSafety
    guard capacity >= 256 else { return nil }
    contextTokens = context
    sourceCapacity = capacity
    usesReviewedContext = capabilities.isVerified || capabilities.source == .userOverride
  }

  static func upperBound(_ text: String) -> Int { text.utf8.count }
}
