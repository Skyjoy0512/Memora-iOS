import Foundation

/// One agent conversation with a cloud model that can call tools. It keeps the
/// provider's own message format, so what the model said (including thinking
/// and tool calls) goes back to it exactly as it came.
@MainActor
final class CloudAgentSession {
  private let llm: LLMSelection
  private let key: String
  private let system: String
  /// Fixed for the session, so the model sees the same tools on every turn.
  private let tools: [AgentTool] = AgentTool.offered
  /// Tools from connected MCP servers, loaded before the first turn.
  var externalTools: [MCPTool] = []
  private var messages: [[String: Any]] = []

  /// Returns nil when there is no key for the provider; the caller says so.
  init?(llm: LLMSelection, system: String) {
    guard let key = KeychainStore.string(forKey: llm.provider.keychainAccount), !key.isEmpty else {
      return nil
    }
    self.llm = llm
    self.key = key
    self.system = system
  }

  func addUserMessage(_ text: String) {
    messages.append(["role": "user", "content": text])
  }

  /// Hands the tools' results back, in the order the model asked for them.
  func addToolResults(_ results: [(call: AgentToolCall, outcome: AgentToolOutcome)]) {
    if llm.provider.usesAnthropicAPI {
      messages.append([
        "role": "user",
        "content": results.map { result in
          [
            "type": "tool_result",
            "tool_use_id": result.call.id,
            "content": result.outcome.text,
            "is_error": result.outcome.isError
          ] as [String: Any]
        }
      ])
    } else {
      for result in results {
        messages.append([
          "role": "tool",
          "tool_call_id": result.call.id,
          "content": result.outcome.text
        ])
      }
    }
  }

  /// Asks for the model's next turn.
  func next() async throws -> AgentTurn {
    guard !llm.modelID.isEmpty else { throw AIAnswerFailure.modelUnavailable }
    do {
      return llm.provider.usesAnthropicAPI ? try await anthropicTurn() : try await chatCompletionsTurn()
    } catch let failure as AIAnswerFailure {
      throw failure
    } catch is CancellationError {
      throw AIAnswerFailure.cancelled
    } catch let error as URLError {
      throw CloudAIService.failure(for: error)
    } catch {
      throw AIAnswerFailure.server
    }
  }

  // MARK: - Anthropic

  private func anthropicTurn() async throws -> AgentTurn {
    var request = URLRequest(url: LLMProvider.anthropic.baseURL.appendingPathComponent("messages"))
    request.httpMethod = "POST"
    // Not streamed, so nothing arrives until a whole turn is written; a long
    // document in one tool call can take minutes.
    request.timeoutInterval = 600
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    var body: [String: Any] = [
      "model": llm.modelID,
      // A document is written inside one tool call, so the cap leaves room for
      // a long one after the model's thinking.
      "max_tokens": 32_000,
      "system": system,
      "tools": tools.map { tool in
        ["name": tool.rawValue, "description": tool.summary, "input_schema": tool.inputSchema]
      } + externalTools.map { tool in
        ["name": tool.agentName, "description": "[\(tool.serverName)] \(tool.summary)", "input_schema": tool.schemaObject]
      },
      "messages": messages
    ]
    // Matches `CloudAIService`: these models may decline on a classifier, and
    // the fallback lets another model answer instead.
    if llm.modelID == "claude-opus-5" || llm.modelID == "claude-fable-5-1" {
      request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
      body["fallbacks"] = "default"
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    try CloudAIService.validate(response)
    guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = decoded["content"] as? [[String: Any]] else {
      throw AIAnswerFailure.server
    }
    if decoded["stop_reason"] as? String == "refusal" { throw AIAnswerFailure.refused }

    // The whole turn goes back unchanged: thinking blocks must accompany the
    // tool calls they led to.
    messages.append(["role": "assistant", "content": content])

    let text = content
      .filter { $0["type"] as? String == "text" }
      .compactMap { $0["text"] as? String }
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let calls = content
      .filter { $0["type"] as? String == "tool_use" }
      .compactMap { block -> AgentToolCall? in
        guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
        return AgentToolCall(id: id, name: name, arguments: block["input"] as? [String: Any] ?? [:])
      }
    return AgentTurn(text: text, toolCalls: calls)
  }

  // MARK: - OpenAI-compatible

  private func chatCompletionsTurn() async throws -> AgentTurn {
    var request = URLRequest(url: llm.provider.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    // Not streamed, so nothing arrives until a whole turn is written; a long
    // document in one tool call can take minutes.
    request.timeoutInterval = 600
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    if llm.provider == .openRouter {
      request.setValue("Memora", forHTTPHeaderField: "X-Title")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": llm.modelID,
      "messages": [["role": "system", "content": system]] + messages,
      "tools": tools.map { tool in
        [
          "type": "function",
          "function": [
            "name": tool.rawValue,
            "description": tool.summary,
            "parameters": tool.inputSchema
          ] as [String: Any]
        ] as [String: Any]
      } + externalTools.map { tool in
        [
          "type": "function",
          "function": [
            "name": tool.agentName,
            "description": "[\(tool.serverName)] \(tool.summary)",
            "parameters": tool.schemaObject
          ] as [String: Any]
        ] as [String: Any]
      }
    ] as [String: Any])

    let (data, response) = try await URLSession.shared.data(for: request)
    try CloudAIService.validate(response)
    guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = decoded["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any] else {
      throw AIAnswerFailure.server
    }

    let text = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let rawCalls = message["tool_calls"] as? [[String: Any]] ?? []

    // Tool calls go back as they came, so provider extras (such as a thought
    // signature) survive; so does reasoning some providers require back.
    var assistant: [String: Any] = ["role": "assistant", "content": text]
    if !rawCalls.isEmpty {
      assistant["tool_calls"] = rawCalls
    }
    if let reasoning = message["reasoning_content"] {
      assistant["reasoning_content"] = reasoning
    }
    messages.append(assistant)

    let calls = rawCalls.compactMap { call -> AgentToolCall? in
      guard let id = call["id"] as? String,
            let function = call["function"] as? [String: Any],
            let name = function["name"] as? String else { return nil }
      let argumentText = function["arguments"] as? String ?? "{}"
      let arguments = argumentText.data(using: .utf8)
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
      return AgentToolCall(id: id, name: name, arguments: arguments)
    }
    return AgentTurn(text: text, toolCalls: calls)
  }
}
