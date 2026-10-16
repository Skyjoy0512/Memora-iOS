import Foundation

/// Reserve before dispatch, refund only a complete provider-reported count.
/// Unknown usage and failed requests keep their reservation; neither is free.
struct AgentOutputBudget {
  static let maximumTokens = 128_000
  private(set) var chargedTokens = 0
  private var reservation: Int?
  private var exhausted = false

  mutating func reserve(maximum: Int) throws -> Int {
    guard maximum > 0, reservation == nil, !exhausted,
          chargedTokens < Self.maximumTokens else { throw AIAnswerFailure.executionLimit }
    let allowance = min(maximum, Self.maximumTokens - chargedTokens)
    chargedTokens += allowance
    reservation = allowance
    return allowance
  }

  mutating func settle(reportedOutputTokens: Int?) throws {
    guard let reserved = reservation else { throw AIAnswerFailure.executionLimit }
    reservation = nil
    guard let actual = reportedOutputTokens, actual >= 0 else { return }
    guard actual <= reserved else {
      exhausted = true
      throw AIAnswerFailure.executionLimit
    }
    chargedTokens -= reserved - actual
  }
}
