import Foundation

/// Keeps a long tool conversation inside the model's input room without
/// silently discarding the request or the recent turns. Old tool results are
/// replaced by a short note; the model can call the same read again, so the
/// original record is never destroyed.
enum AgentContextCompactor {
  static let placeholder = "（以前のツール結果は長いため省略しました。必要なら同じ読み取りを再実行してください。）"

  /// Messages are provider-shaped JSON. User and assistant turns stay intact;
  /// only old `tool` results and Anthropic `tool_result` blocks are shortened.
  static func compact(_ messages: [[String: Any]], keepRecent: Int = 6,
                      characterBudget: Int) -> [[String: Any]] {
    guard characterBudget > 0, estimatedCharacters(messages) > characterBudget else { return messages }
    var result = messages
    let protected = max(0, result.count - max(0, keepRecent))
    // Keep the first user turn: it holds the request and its scope.
    let firstUser = result.firstIndex { ($0["role"] as? String) == "user" } ?? 0
    for index in 0..<protected where index != firstUser {
      guard estimatedCharacters(result) > characterBudget * 3 / 4 else { break }
      let role = result[index]["role"] as? String
      if role == "tool" {
        if let content = result[index]["content"] as? String, content.count > 400 {
          result[index]["content"] = String(content.prefix(400)) + "\n" + placeholder
        }
      } else if role == "user", let blocks = result[index]["content"] as? [[String: Any]] {
        var changed = blocks
        for blockIndex in changed.indices
        where (changed[blockIndex]["type"] as? String) == "tool_result" {
          if let content = changed[blockIndex]["content"] as? String, content.count > 400 {
            changed[blockIndex]["content"] = String(content.prefix(400)) + "\n" + placeholder
          }
        }
        result[index]["content"] = changed
      }
    }
    return result
  }

  /// A character estimate, matching the conservative budgeting used elsewhere.
  static func estimatedCharacters(_ messages: [[String: Any]]) -> Int {
    var total = 0
    for message in messages {
      if let text = message["content"] as? String {
        total += text.count
      } else if let blocks = message["content"] as? [[String: Any]] {
        for block in blocks {
          if let text = block["content"] as? String { total += text.count }
          if let text = block["text"] as? String { total += text.count }
        }
      }
      if let calls = message["tool_calls"] as? [[String: Any]] {
        for call in calls {
          if let function = call["function"] as? [String: Any],
             let arguments = function["arguments"] as? String {
            total += arguments.count
          }
        }
      }
      total += 64
    }
    return total
  }
}
