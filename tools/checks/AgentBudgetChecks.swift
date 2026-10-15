import Foundation

@main
enum AgentBudgetChecks {
  static func main() throws {
    let start = ContinuousClock.now
    var budget = AgentSessionBudget()
    for _ in 0..<AgentSessionBudget.maximumRequests { try budget.reserveRequest(bytes: 1, now: start) }
    rejected { try budget.reserveRequest(bytes: 1, now: start) }
    precondition(budget.requests == 16)
    budget = AgentSessionBudget()
    rejected { try budget.reserveRequest(bytes: -1, now: start) }
    rejected { try budget.reserveRequest(bytes: Int.max, now: start) }
    try budget.reserveRequest(bytes: 512 * 1024, now: start)
    precondition(budget.hasTime(at: start.advanced(by: .seconds(599))))
    rejected { try budget.reserveRequest(bytes: 1, now: start.advanced(by: .seconds(600))) }
    rejected { try budget.acceptResponse(bytes: 1, now: start.advanced(by: .seconds(600))) }
    budget = AgentSessionBudget()
    for _ in 0..<8 { try budget.reserveRequest(bytes: 512 * 1024, now: start) }
    rejected { try budget.reserveRequest(bytes: 1, now: start) }
    try budget.acceptResponse(bytes: 2 * 1024 * 1024, now: start)
    rejected { try budget.acceptResponse(bytes: 1, now: start) }
    print("AgentBudgetChecks: passed (16 requests, per/total bytes, exact deadline, negative/overflow rejection, no network or keys)")
  }

  static func rejected(_ action: () throws -> Void) {
    do { try action(); preconditionFailure("Budget admitted an invalid request") }
    catch let failure as AIAnswerFailure { precondition(failure == .executionLimit) }
    catch { preconditionFailure("Unexpected budget error") }
  }
}
