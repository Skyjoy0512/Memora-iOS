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
    let reasoning: [[String: Any]] = [["role": "assistant", "content": "", "reasoning_content": long]]
    precondition(AgentContextCompactor.estimatedCharacters(reasoning) > long.count)
    let thinking: [[String: Any]] = [["role": "assistant", "content": [["type": "thinking", "thinking": long, "signature": long]]]]
    precondition(AgentContextCompactor.estimatedCharacters(thinking) > long.count * 2)
    let nested: [[String: Any]] = [["role": "user", "content": [["type": "tool_result", "tool_use_id": "x",
      "content": [["type": "text", "text": long]]]]]]
    precondition(AgentContextCompactor.estimatedCharacters(nested) > long.count)

    // Repeated reads are deduplicated: the first copy stays, later old copies
    // point at its tool id, and recent turns are not rewritten.
    let same = String(repeating: "同じ検索結果。", count: 700)
    var duplicates: [[String: Any]] = [["role": "user", "content": "依頼"]]
    for index in 0..<6 {
      duplicates.append(["role": "assistant", "content": "", "tool_calls": [
        ["id": "d\(index)", "function": ["name": "search_records", "arguments": "{}"]]
      ]])
      duplicates.append(["role": "tool", "tool_call_id": "d\(index)", "content": same])
    }
    duplicates.append(["role": "user", "content": "最近"])
    let deduplicated = AgentContextCompactor.compact(duplicates, keepRecent: 2, characterBudget: 20_000)
    precondition(deduplicated.count == duplicates.count)
    precondition(deduplicated[2]["content"] as? String == same)
    precondition(deduplicated[4]["content"] as? String == "（同じ内容のツール結果は d0 にあります。）")
    precondition(deduplicated[4]["tool_call_id"] as? String == "d1")
    precondition(deduplicated[12]["content"] as? String == same, "recent tool result stays intact")
    let anthropicDuplicates: [[String: Any]] = [
      ["role": "user", "content": "依頼"],
      ["role": "user", "content": [
        ["type": "tool_result", "tool_use_id": "a", "content": same],
        ["type": "tool_result", "tool_use_id": "b", "content": same]
      ]],
      ["role": "user", "content": "最近"],
      ["role": "user", "content": "最近2"]
    ]
    let deduplicatedAnthropic = AgentContextCompactor.compact(anthropicDuplicates, keepRecent: 2, characterBudget: 8_000)
    let dedupBlocks = deduplicatedAnthropic[1]["content"] as? [[String: Any]]
    precondition(dedupBlocks?[0]["tool_use_id"] as? String == "a")
    precondition(dedupBlocks?[0]["content"] as? String == same)
    precondition(dedupBlocks?[1]["tool_use_id"] as? String == "b")
    precondition((dedupBlocks?[1]["content"] as? String)?.contains("a") == true)

    print("AgentContextCompactorChecks: passed (keeps request/recent turns, deduplicates repeated tool results by tool id, shortens old tool results, preserves tool-call pairing, both API shapes, no-op within budget)")
  }
}
