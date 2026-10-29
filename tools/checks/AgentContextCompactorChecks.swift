import Foundation

@main
enum AgentContextCompactorChecks {
  static func main() {
    let long = String(repeating: "会議の決定事項。", count: 2_000)
    var messages: [[String: Any]] = [
      ["role": "user", "content": "元の依頼: 販売システムの資料を作る"],
      ["role": "assistant", "content": "検索します"]
    ]
    for index in 0..<20 {
      messages.append(["role": "assistant", "content": "", "tool_calls": [
        ["id": "c\(index)", "function": ["name": "search_records", "arguments": "{\"query\":\"販売\"}"]]
      ]])
      messages.append(["role": "tool", "tool_call_id": "c\(index)", "content": long])
    }
    messages.append(["role": "user", "content": "最近の依頼"])

    let before = AgentContextCompactor.estimatedCharacters(messages)
    let compacted = AgentContextCompactor.compact(messages, keepRecent: 6, characterBudget: 20_000)
    let after = AgentContextCompactor.estimatedCharacters(compacted)
    precondition(after < before)
    precondition(compacted[0]["content"] as? String == "元の依頼: 販売システムの資料を作る")
    precondition(compacted.last?["content"] as? String == "最近の依頼")
    // Old tool results become a note; the recent ones keep their text.
    precondition((compacted[3]["content"] as? String)?.contains("省略しました") == true)
    precondition((compacted[compacted.count - 2]["content"] as? String)?.hasPrefix("会議の決定事項") == true)
    // Tool calls and their IDs stay paired so the provider accepts the turn.
    precondition((compacted[2]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "c0")

    let anthropic: [[String: Any]] = [
      ["role": "user", "content": "依頼"],
      ["role": "user", "content": [
        ["type": "tool_result", "tool_use_id": "a", "content": long],
        ["type": "tool_result", "tool_use_id": "b", "content": long]
      ]],
      ["role": "user", "content": "最近"]
    ]
    let compactedAnthropic = AgentContextCompactor.compact(anthropic, keepRecent: 1, characterBudget: 1_000)
    let blocks = compactedAnthropic[1]["content"] as? [[String: Any]]
    precondition(blocks?[0]["tool_use_id"] as? String == "a")
    precondition((blocks?[0]["content"] as? String)?.contains("省略しました") == true)

    // Under budget, nothing changes.
    let small: [[String: Any]] = [["role": "user", "content": "短い"]]
    precondition(AgentContextCompactor.compact(small, characterBudget: 10_000).count == 1)
    precondition((AgentContextCompactor.compact(small, characterBudget: 10_000)[0]["content"] as? String) == "短い")

    print("AgentContextCompactorChecks: passed (keeps request/recent turns, shortens old tool results, preserves tool-call pairing, both API shapes, no-op within budget)")
  }
}
