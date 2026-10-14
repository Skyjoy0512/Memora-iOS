import Foundation

@MainActor
enum AgentConversationLoop {
  struct Limits {
    var turns = 16
    var toolCalls = 24
    var callsPerTurn = 24
  }

  static func run(
    limits: Limits = Limits(),
    isAuthorized: () -> Bool,
    next: () async throws -> AgentTurn,
    execute: (AgentToolCall) async -> AgentToolOutcome,
    canExecute: () -> Bool = { true },
    accept: (AgentTurn, [(call: AgentToolCall, outcome: AgentToolOutcome)]) -> Void
  ) async -> AIAnswerResult {
    let maximumTurns = min(max(limits.turns, 1), 16)
    let maximumCalls = min(max(limits.toolCalls, 0), 24)
    let maximumCallsPerTurn = min(max(limits.callsPerTurn, 1), 24)
    var calls = 0
    var usedCallIDs: Set<String> = []
    var lastText = ""
    for _ in 0..<maximumTurns {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      guard isAuthorized() else { return .failure(.contextChanged) }
      let turn: AgentTurn
      do { turn = try await next() }
      catch is CancellationError { return .failure(.cancelled) }
      catch let failure as AIAnswerFailure { return .failure(failure) }
      catch { return .failure(.server) }
      guard !Task.isCancelled else { return .failure(.cancelled) }
      guard isAuthorized() else { return .failure(.contextChanged) }
      let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty { lastText = text }
      guard !turn.toolCalls.isEmpty else {
        accept(turn, [])
        return text.isEmpty ? .failure(.empty) : .answer(text)
      }
      guard turn.toolCalls.count <= maximumCallsPerTurn else { return .failure(.server) }
      // Reject an entire malformed batch before any operation can run or be replayed.
      let ids = turn.toolCalls.map(\.id)
      guard Set(ids).count == ids.count, usedCallIDs.isDisjoint(with: ids),
            turn.toolCalls.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.name.isEmpty && $0.name.count <= 100 }) else {
        return .failure(.server)
      }
      usedCallIDs.formUnion(ids)
      var results: [(call: AgentToolCall, outcome: AgentToolOutcome)] = []
      for call in turn.toolCalls {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard isAuthorized() else { return .failure(.contextChanged) }
        guard calls < maximumCalls, canExecute() else {
          return .answer("ツール実行上限に達したため停止しました。作業は未完了です。確認できた結果を見て、必要な続きだけを依頼してください。")
        }
        calls += 1
        let outcome = await execute(call)
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard isAuthorized() else { return .failure(.contextChanged) }
        results.append((call, outcome))
      }
      accept(turn, results)
    }
    let note = "会話の実行上限に達したため停止しました。作業は未完了です。必要な続きだけを新しい依頼で指定してください。"
    return .answer(lastText.isEmpty ? note : lastText + "\n\n" + note)
  }
}
