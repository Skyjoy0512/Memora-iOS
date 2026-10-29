import Foundation

/// One ephemeral owner per request; sharing a budget never shares tool grants.
@MainActor
final class AgentRunBudget {
  private var requests = AgentSessionBudget()
  private var output = AgentOutputBudget()
  private var cancelled = false
  private var exceeded = false

  init(requests: AgentSessionBudget = AgentSessionBudget(), output: AgentOutputBudget = AgentOutputBudget()) {
    self.requests = requests
    self.output = output
  }

  var isStopped: Bool { cancelled || exceeded || output.isExhausted }
  var requestCount: Int { requests.requests }
  var chargedOutputTokens: Int { output.chargedTokens }

  func check(at now: ContinuousClock.Instant = .now) throws {
    try Task.checkCancellation()
    guard !cancelled else { throw AIAnswerFailure.cancelled }
    guard !exceeded, !output.isExhausted else { throw AIAnswerFailure.executionLimit }
    guard requests.hasTime(at: now) else {
      exceeded = true
      throw AIAnswerFailure.executionLimit
    }
  }

  func reserveRequest(bytes: Int, now: ContinuousClock.Instant = .now) throws {
    try check(at: now)
    do { try requests.reserveRequest(bytes: bytes, now: now) }
    catch { exceeded = true; throw error }
  }

  func acceptResponse(bytes: Int, now: ContinuousClock.Instant = .now) throws {
    try check(at: now)
    do { try requests.acceptResponse(bytes: bytes, now: now) }
    catch { exceeded = true; throw error }
  }

  func reserveOutput(maximum: Int) throws -> AgentOutputBudget.Reservation {
    try check()
    do { return try output.reserve(maximum: maximum) }
    catch {
      // In-flight replies can still refund capacity; don't discard them merely
      // because the currently reserved total fills the budget.
      if output.chargedTokens == output.limitTokens, !output.hasPendingReservations { exceeded = true }
      throw error
    }
  }

  func settleOutput(_ reservation: AgentOutputBudget.Reservation, reportedOutputTokens: Int?) throws {
    try check()
    try output.settle(reservation, reportedOutputTokens: reportedOutputTokens)
  }

  func cancel() { cancelled = true }
}
