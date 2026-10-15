import Foundation

@main
@MainActor
struct AgentConversationLoopChecks {
  static func main() async {
    let call = AgentToolCall(id: "lookup-1", name: "read_record", arguments: ["id": UUID().uuidString])
    var turns = [AgentTurn(text: "", toolCalls: [call]), AgentTurn(text: "確認しました。", toolCalls: [])]
    var executed = 0
    var results: [AgentToolOutcome] = []
    let complete = await AgentConversationLoop.run(isAuthorized: { true }, next: { turns.removeFirst() },
      execute: { _ in executed += 1; return AgentToolOutcome(text: "本文") },
      accept: { _, batch in results += batch.map(\.outcome) })
    precondition(complete.text == "確認しました。" && executed == 1 && results.first?.text == "本文")

    var authorized = true
    var requests = 0
    let revoked = await AgentConversationLoop.run(isAuthorized: { authorized },
      next: { requests += 1; authorized = false; return AgentTurn(text: "古い回答", toolCalls: [call]) },
      execute: { _ in preconditionFailure("Revoked call executed") }, accept: { _, _ in preconditionFailure("Revoked result accepted") })
    expect(revoked, .contextChanged)
    precondition(requests == 1)
    let blocked = await AgentConversationLoop.run(isAuthorized: { false },
      next: { preconditionFailure("Unauthorized request sent") }, execute: { _ in preconditionFailure() }, accept: { _, _ in })
    expect(blocked, .contextChanged)

    authorized = true
    executed = 0
    let betweenCalls = await AgentConversationLoop.run(isAuthorized: { authorized },
      next: { AgentTurn(text: "", toolCalls: [call, AgentToolCall(id: "lookup-2", name: "read_record", arguments: [:])]) },
      execute: { _ in executed += 1; authorized = false; return AgentToolOutcome(text: "stale") },
      accept: { _, _ in preconditionFailure("Stale batch accepted") })
    expect(betweenCalls, .contextChanged)
    precondition(executed == 1)
    for invalidBatch in [[call, call], [AgentToolCall(id: "", name: "read_record", arguments: [:])]] {
      let invalid = await AgentConversationLoop.run(isAuthorized: { true }, next: { AgentTurn(text: "", toolCalls: invalidBatch) },
        execute: { _ in preconditionFailure("Malformed batch executed") }, accept: { _, _ in })
      expect(invalid, .server)
    }
    turns = [AgentTurn(text: "", toolCalls: [call]), AgentTurn(text: "", toolCalls: [call])]
    executed = 0
    let replay = await AgentConversationLoop.run(isAuthorized: { true }, next: { turns.removeFirst() },
      execute: { _ in executed += 1; return AgentToolOutcome(text: "done") }, accept: { _, _ in })
    expect(replay, .server)
    precondition(executed == 1)

    requests = 0
    executed = 0
    let limited = await AgentConversationLoop.run(limits: .init(turns: 16, toolCalls: 2, callsPerTurn: 4), isAuthorized: { true },
      next: { requests += 1; return AgentTurn(text: "", toolCalls: [AgentToolCall(id: "call-\(requests)", name: "read_record", arguments: [:])]) },
      execute: { _ in executed += 1; return AgentToolOutcome(text: "done") }, accept: { _, _ in })
    precondition(limited.text?.contains("未完了") == true && executed == 2 && requests == 3)
    requests = 0
    let turnLimit = await AgentConversationLoop.run(limits: .init(turns: 2), isAuthorized: { true },
      next: { requests += 1; return AgentTurn(text: "", toolCalls: [AgentToolCall(id: "call-\(requests)", name: "read_record", arguments: [:])]) },
      execute: { _ in AgentToolOutcome(text: "done") }, accept: { _, _ in })
    precondition(turnLimit.text?.contains("未完了") == true && requests == 2)

    turns = [AgentTurn(text: "検索します", toolCalls: [call]), AgentTurn(text: "", toolCalls: [])]
    let empty = await AgentConversationLoop.run(isAuthorized: { true }, next: { turns.removeFirst() },
      execute: { _ in AgentToolOutcome(text: "unavailable", isError: true) }, accept: { _, _ in })
    expect(empty, .empty)
    let interrupted = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return await AgentConversationLoop.run(isAuthorized: { true }, next: { preconditionFailure("Cancelled request sent") },
        execute: { _ in preconditionFailure() }, accept: { _, _ in })
    }
    expect(await interrupted.value, .cancelled)
    let failure = await AgentConversationLoop.run(isAuthorized: { true }, next: { throw AIAnswerFailure.network },
      execute: { _ in preconditionFailure() }, accept: { _, _ in })
    expect(failure, .network)
    let start = ContinuousClock.now
    var moment = start
    var events: [AgentRunEvent] = []
    let expired = await AgentConversationLoop.run(limits: .init(duration: .seconds(2)), isAuthorized: { true },
      next: { moment = start.advanced(by: .seconds(2)); return AgentTurn(text: "", toolCalls: [call]) },
      execute: { _ in preconditionFailure("Expired turn executed a tool") },
      now: { moment }, onEvent: { events.append($0) }, accept: { _, _ in preconditionFailure() })
    expect(expired, .executionLimit)
    precondition(events == [.modelRequested(turn: 1), .finished(modelRequests: 1, toolCalls: 0, elapsedMilliseconds: 2_000)])
    precondition(AgentToolCall(id: "integer", name: "read", arguments: ["limit": Double.nan]).int("limit") == nil)
    precondition(AgentToolCall(id: "integer", name: "read", arguments: ["limit": Double.infinity]).int("limit") == nil)
    print("AgentConversationLoopChecks: passed (mock turns, ordered real loop dispatch, revoke/cancel/empty/failure, bounded calls, replay rejection; no network)")
  }

  private static func expect(_ result: AIAnswerResult, _ failure: AIAnswerFailure) {
    guard case .failure(let actual) = result, actual == failure else { preconditionFailure("Unexpected loop result") }
  }
}
