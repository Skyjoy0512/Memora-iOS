import Foundation

/// Transport completion is not permission to execute a tool. Validate the whole
/// turn before any call reaches the agent's existing authorization/approval path.
enum CloudAgentTurnDecoder {
  static func anthropic(_ response: [String: Any]) throws -> AgentTurn {
    try validateFinish(response["stop_reason"] as? String, allowed: ["end_turn", "stop_sequence", "tool_use"])
    guard response["error"] == nil, let content = response["content"] as? [[String: Any]] else {
      throw AIAnswerFailure.server
    }
    let rawCalls = content.filter { $0["type"] as? String == "tool_use" }
    guard rawCalls.count <= 24 else { throw AIAnswerFailure.executionLimit }
    var identifiers: Set<String> = []
    let calls = try rawCalls.map { block in
      let (id, name) = try identity(id: block["id"], name: block["name"], identifiers: &identifiers)
      guard let arguments = block["input"] as? [String: Any] else { throw AIAnswerFailure.server }
      return AgentToolCall(id: id, name: name, arguments: arguments)
    }
    guard (response["stop_reason"] as? String == "tool_use") == !calls.isEmpty else {
      throw AIAnswerFailure.server
    }
    let text = content.filter { $0["type"] as? String == "text" }
      .compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    let reasoning = content.filter { $0["type"] as? String == "thinking" }
      .compactMap { $0["thinking"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentTurn(text: text, toolCalls: calls, reasoning: reasoning)
  }

  static func chatCompletions(_ response: [String: Any]) throws -> AgentTurn {
    guard response["error"] == nil, let choices = response["choices"] as? [[String: Any]],
          let choice = choices.first, let message = choice["message"] as? [String: Any] else {
      throw AIAnswerFailure.server
    }
    try validateFinish(choice["finish_reason"] as? String, allowed: ["stop", "tool_calls"])
    var rawCalls: [[String: Any]] = []
    if let value = message["tool_calls"], !(value is NSNull) {
      guard let calls = value as? [[String: Any]] else { throw AIAnswerFailure.server }
      rawCalls = calls
    }
    guard rawCalls.count <= 24 else { throw AIAnswerFailure.executionLimit }
    var identifiers: Set<String> = []
    let calls = try rawCalls.map { call in
      guard call["type"] as? String == "function", let function = call["function"] as? [String: Any] else {
        throw AIAnswerFailure.server
      }
      let (id, name) = try identity(id: call["id"], name: function["name"], identifiers: &identifiers)
      guard let argumentText = function["arguments"] as? String,
            let data = argumentText.data(using: .utf8),
            let arguments = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw AIAnswerFailure.server
      }
      return AgentToolCall(id: id, name: name, arguments: arguments)
    }
    guard (choice["finish_reason"] as? String == "tool_calls") == !calls.isEmpty,
          (message["function_call"] == nil || message["function_call"] is NSNull) else { throw AIAnswerFailure.server }
    let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let reasoning = ((message["reasoning_content"] ?? message["reasoning"]) as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentTurn(text: text, toolCalls: calls, reasoning: reasoning)
  }

  private static func validateFinish(_ reason: String?, allowed: Set<String>) throws {
    if reason == "refusal" || reason == "content_filter" { throw AIAnswerFailure.refused }
    if reason == "length" || reason == "max_tokens" || reason == "model_context_window_exceeded" || reason == "pause_turn" {
      throw AIAnswerFailure.connectionLost
    }
    guard let reason, allowed.contains(reason) else { throw AIAnswerFailure.server }
  }

  private static func identity(id: Any?, name: Any?, identifiers: inout Set<String>) throws -> (String, String) {
    guard let id = id as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 200,
          let name = name as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 100,
          identifiers.insert(id).inserted else { throw AIAnswerFailure.server }
    return (id, name)
  }
}
