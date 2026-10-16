import Foundation

@main
@MainActor
struct AgentRunBudgetChecks {
  static func main() async throws {
    let shared = AgentRunBudget()
    try shared.reserveRequest(bytes: 1)
    try shared.acceptResponse(bytes: 1)
    let dispatched = await withTaskGroup(of: Int.self) { group in
      for _ in 0..<3 {
        group.addTask { @MainActor in
          var sent = 0
          for _ in 0..<6 {
            do {
              try shared.reserveRequest(bytes: 1)
              sent += 1
              await Task.yield()
              try shared.acceptResponse(bytes: 1)
            } catch { break }
          }
          return sent
        }
      }
      var total = 1
      for await sent in group { total += sent }
      return total
    }
    precondition(dispatched == 16 && shared.requestCount == 16 && shared.isStopped)
    rejects(.executionLimit) { try shared.reserveRequest(bytes: 1) }
    let fresh = AgentRunBudget()
    try fresh.reserveRequest(bytes: 1)
    precondition(fresh.requestCount == 1 && !fresh.isStopped)

    let byteBound = AgentRunBudget()
    for _ in 0..<8 { try byteBound.reserveRequest(bytes: 512 * 1024) }
    rejects(.executionLimit) { try byteBound.reserveRequest(bytes: 1) }
    let responses = AgentRunBudget()
    try responses.reserveRequest(bytes: 1)
    try responses.acceptResponse(bytes: 1024 * 1024)
    try responses.acceptResponse(bytes: 1024 * 1024)
    rejects(.executionLimit) { try responses.acceptResponse(bytes: 1) }

    let output = AgentRunBudget()
    let tickets = try (0..<4).map { _ in try output.reserveOutput(maximum: 32_000) }
    precondition(output.chargedOutputTokens == 128_000)
    rejects(.executionLimit) { _ = try output.reserveOutput(maximum: 1) }
    // Pending reservations may still report real usage; capacity contention
    // must not globally cancel their already-started requests.
    precondition(!output.isStopped)
    try output.settleOutput(tickets[2], reportedOutputTokens: 1_000)
    let replacement = try output.reserveOutput(maximum: 32_000)
    precondition(replacement.maximumTokens == 31_000 && output.chargedOutputTokens == 128_000)
    rejects(.executionLimit) { try output.settleOutput(tickets[2], reportedOutputTokens: 0) }
    let forged = AgentOutputBudget.Reservation(id: tickets[0].id, maximumTokens: 1)
    rejects(.executionLimit) { try output.settleOutput(forged, reportedOutputTokens: 0) }
    rejects(.executionLimit) { try fresh.settleOutput(tickets[0], reportedOutputTokens: 0) }
    precondition(output.chargedOutputTokens == 128_000 && fresh.chargedOutputTokens == 0)
    try output.settleOutput(tickets[0], reportedOutputTokens: nil)
    try output.settleOutput(tickets[1], reportedOutputTokens: 2_000)
    try output.settleOutput(tickets[3], reportedOutputTokens: 3_000)
    try output.settleOutput(replacement, reportedOutputTokens: nil)
    precondition(output.chargedOutputTokens == 69_000)

    let fullyCharged = AgentRunBudget()
    for _ in 0..<4 {
      let ticket = try fullyCharged.reserveOutput(maximum: 32_000)
      try fullyCharged.settleOutput(ticket, reportedOutputTokens: nil)
    }
    rejects(.executionLimit) { _ = try fullyCharged.reserveOutput(maximum: 1) }
    precondition(fullyCharged.isStopped)

    let exceeded = AgentRunBudget()
    let small = try exceeded.reserveOutput(maximum: 1)
    rejects(.executionLimit) { try exceeded.settleOutput(small, reportedOutputTokens: 2) }
    precondition(exceeded.isStopped)
    rejects(.executionLimit) { try exceeded.reserveRequest(bytes: 1) }

    let deadline = AgentRunBudget()
    let start = ContinuousClock.now
    try deadline.reserveRequest(bytes: 1, now: start)
    try deadline.check(at: start.advanced(by: .seconds(599)))
    rejects(.executionLimit) { try deadline.check(at: start.advanced(by: .seconds(600))) }
    precondition(deadline.isStopped)

    let cancelled = AgentRunBudget()
    cancelled.cancel()
    rejects(.cancelled) { try cancelled.reserveRequest(bytes: 1) }
    rejects(.cancelled) { _ = try cancelled.reserveOutput(maximum: 1) }

    let late = AgentRunBudget()
    var release: CheckedContinuation<Void, Never>?
    var executed = 0
    var accepted = 0
    let pending = Task { @MainActor in
      await AgentConversationLoop.run(isAuthorized: { true }, next: {
        try late.reserveRequest(bytes: 1)
        await withCheckedContinuation { release = $0 }
        return AgentTurn(text: "late", toolCalls: [AgentToolCall(id: "late", name: "read_record", arguments: [:])])
      }, checkExecution: { try late.check() }, execute: { _ in
        executed += 1
        return AgentToolOutcome(text: "must not execute")
      }, accept: { _, _ in accepted += 1 })
    }
    while release == nil { await Task.yield() }
    late.cancel()
    release?.resume()
    let lateResult = await pending.value
    precondition(lateResult.failure == .cancelled && executed == 0 && accepted == 0 && late.requestCount == 1)

    let duringTools = AgentRunBudget()
    let calls = (0..<2).map { AgentToolCall(id: "read\($0)", name: "read_record", arguments: [:]) }
    executed = 0
    let toolStop = await AgentConversationLoop.run(isAuthorized: { true }, next: { AgentTurn(text: "", toolCalls: calls) },
      checkExecution: { try duringTools.check() }, execute: { _ in
        executed += 1
        duringTools.cancel()
        return AgentToolOutcome(text: "read before cancellation")
      }, accept: { _, _ in preconditionFailure("Stopped batch accepted") })
    precondition(toolStop.failure == .cancelled && executed == 1)

    let strict = await AgentConversationLoop.run(limits: .init(turns: 1, returnsLimitFailure: true), isAuthorized: { true },
      next: { AgentTurn(text: "途中の前置き", toolCalls: [calls[0]]) }, execute: { _ in AgentToolOutcome(text: "fixture") }, accept: { _, _ in })
    precondition(strict.failure == .executionLimit && strict.text == nil)
    let noTools = await AgentConversationLoop.run(limits: .init(returnsLimitFailure: true), isAuthorized: { true },
      next: { AgentTurn(text: "", toolCalls: [calls[0]]) }, execute: { _ in preconditionFailure("Tool limit bypassed") },
      canExecute: { false }, accept: { _, _ in })
    precondition(noTools.failure == .executionLimit)
    print("AgentRunBudgetChecks: passed (parent + 3 children share 16 requests/bytes/time/output, concurrent reservation identity/refunds, no overcommit, cancellation/late reply/tool stop, strict child completion; mocks only)")
  }

  static func rejects(_ expected: AIAnswerFailure, _ action: () throws -> Void) {
    do { try action(); preconditionFailure("Shared run budget accepted a forbidden operation") }
    catch let failure as AIAnswerFailure { precondition(failure == expected) }
    catch { preconditionFailure("Unexpected shared budget error") }
  }
}
