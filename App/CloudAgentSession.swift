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
  private let tools: [AgentTool]
  private let toolDescriptions: [AgentTool: String]
  /// A copied configuration lets offline checks intercept every request without
  /// replacing the production request builder, stream reader or turn decoder.
  private let sessionConfiguration: URLSessionConfiguration
  /// Tools from connected MCP servers, loaded before the first turn.
  var externalTools: [MCPTool] = []
  private var messages: [[String: Any]] = []
  let runBudget: AgentRunBudget
  let capabilities: ModelCapabilities
  private let contextTask: ContextTaskKind

  /// Returns nil when there is no key for the provider; the caller says so.
  /// `tools` narrows what the model is offered; resident agents get only the
  /// reading tools.
  init?(llm: LLMSelection, system: String, tools: [AgentTool]? = nil, toolDescriptions: [AgentTool: String] = [:], runBudget: AgentRunBudget? = nil, sessionConfiguration: URLSessionConfiguration = .ephemeral,
        contextTask: ContextTaskKind = .agent, capabilityOverrides: [String: ModelCapabilityOverride]? = nil) {
    guard llm.supportsToolCalling, let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return nil
    }
    self.llm = llm
    self.key = key
    self.system = system
    self.tools = tools ?? AgentTool.offered
    self.toolDescriptions = toolDescriptions
    self.sessionConfiguration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
    self.sessionConfiguration.timeoutIntervalForResource = 600
    let capabilities = capabilityOverrides.map { ModelCapabilities.resolve(llm: llm, overrides: $0) }
      ?? ModelCapabilities.resolve(llm: llm)
    self.capabilities = capabilities
    self.contextTask = contextTask
    self.runBudget = runBudget ?? AgentRunBudget(capabilities: capabilities)
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
  func next(onText: (@MainActor (String) -> Void)? = nil) async throws -> AgentTurn {
    guard !llm.modelID.isEmpty else { throw AIAnswerFailure.modelUnavailable }
    try Task.checkCancellation()
    try runBudget.check()
    do {
      return llm.provider.usesAnthropicAPI ? try await anthropicTurn(onText: onText) : try await chatCompletionsTurn(onText: onText)
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

  /// The outbound copy is shortened when the run has grown past the model's
  /// input room. The stored messages stay intact for local accounting.
  private func outboundMessages() -> [[String: Any]] {
    let budget = TokenBudgetManager.budget(capabilities: capabilities, task: contextTask).inputCharacterBudget
    return AgentContextCompactor.compact(messages, characterBudget: max(0, budget * 2 / 3))
  }

  private func requestBody(_ body: [String: Any]) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: body)
    guard data.count <= capabilities.maximumRequestBytes else { throw AIAnswerFailure.executionLimit }
    // Include system instructions, schemas and provider thinking/signatures.
    // Compaction preserves the request and recent turns; if those cannot fit,
    // stop before sending rather than silently dropping their evidence.
    let input = body.filter { ["system", "messages", "tools"].contains($0.key) }
    let inputData = try JSONSerialization.data(withJSONObject: input)
    let budget = TokenBudgetManager.budget(capabilities: capabilities, task: contextTask).inputCharacterBudget
    guard String(decoding: inputData, as: UTF8.self).count <= budget else { throw AIAnswerFailure.executionLimit }
    return data
  }

  private func boundedResponse(for request: URLRequest) async throws -> [String: Any] {
    let session = URLSession(configuration: sessionConfiguration)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    try CloudAIService.validate(response)
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < AgentSessionBudget.maximumResponseBytes else { throw AIAnswerFailure.executionLimit }
      data.append(byte)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
    return object
  }

  private func reserveOutput(in body: inout [String: Any], isStreaming: Bool) throws -> AgentOutputBudget.Reservation? {
    guard let policy = AgentGenerationPolicy.resolve(provider: llm.provider, modelID: llm.modelID,
      hasCustomEndpoint: llm.endpoint != nil || llm.credentialAccount != nil) else { return nil }
    let plannedOutput = TokenBudgetManager.budget(capabilities: capabilities, task: contextTask).outputTokens
    let maximum = min(policy.maximumOutputTokens, plannedOutput)
    var preflight = body
    policy.apply(to: &preflight, allowance: maximum, isStreaming: isStreaming)
    _ = try requestBody(preflight)
    let reservation = try runBudget.reserveOutput(maximum: maximum)
    policy.apply(to: &body, allowance: reservation.maximumTokens, isStreaming: isStreaming)
    return reservation
  }

  private func settleOutput(_ response: [String: Any], reserved: AgentOutputBudget.Reservation?) throws {
    guard let reserved else { return }
    let usage = CloudTokenUsage(response: response, usesAnthropicAPI: llm.provider.usesAnthropicAPI)
    try runBudget.settleOutput(reserved, reportedOutputTokens: usage.outputTokens)
  }

  // MARK: - Anthropic

  private func anthropicTurn(onText: (@MainActor (String) -> Void)?) async throws -> AgentTurn {
    var request = URLRequest(url: LLMProvider.anthropic.baseURL.appendingPathComponent("messages"))
    request.httpMethod = "POST"
    // Tool arguments may hold a long document, so the full turn gets the same deadline as streaming.
    request.timeoutInterval = 600
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    var body: [String: Any] = [
      "model": llm.modelID,
      // A document is written inside one tool call, so the cap leaves room for
      // a long one after the model's thinking. It never exceeds what the model
      // accepts as output.
      "max_tokens": TokenBudgetManager.budget(capabilities: capabilities, task: contextTask).outputTokens,
      "system": system,
      "tools": tools.map { tool in
        ["name": tool.rawValue, "description": toolDescriptions[tool] ?? tool.summary, "input_schema": tool.inputSchema]
      } + externalTools.map { tool in
        ["name": tool.agentName, "description": "[\(tool.serverName)] \(tool.summary)", "input_schema": tool.schemaObject]
      },
      "messages": outboundMessages()
    ]
    // Matches `CloudAIService`: these models may decline on a classifier, and
    // the fallback lets another model answer instead.
    if llm.modelID == "claude-opus-5" || llm.modelID == "claude-fable-5-1" {
      request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
      body["fallbacks"] = "default"
    }
    let outputIsReserved = try reserveOutput(in: &body, isStreaming: onText != nil)
    request.httpBody = try requestBody(body)

    try runBudget.reserveRequest(bytes: request.httpBody?.count ?? 0)
    let decoded: [String: Any]
    if let onText {
      decoded = try await CloudTurnStreaming.response(for: request, provider: .anthropic, onText: onText, sessionConfiguration: sessionConfiguration)
    } else {
      decoded = try await boundedResponse(for: request)
    }
    try settleOutput(decoded, reserved: outputIsReserved)
    try runBudget.acceptResponse(bytes: JSONSerialization.data(withJSONObject: decoded).count)
    guard let content = decoded["content"] as? [[String: Any]] else { throw AIAnswerFailure.server }
    let turn = try CloudAgentTurnDecoder.anthropic(decoded)
    // Preserve provider thinking/signatures only after the entire turn validates.
    messages.append(["role": "assistant", "content": content])
    return turn
  }

  // MARK: - OpenAI-compatible

  private func chatCompletionsTurn(onText: (@MainActor (String) -> Void)?) async throws -> AgentTurn {
    var request = URLRequest(url: llm.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    // Tool arguments may hold a long document, so the full turn gets the same deadline as streaming.
    request.timeoutInterval = 600
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    if llm.provider == .openRouter {
      request.setValue("Memora", forHTTPHeaderField: "X-Title")
    }
    var body: [String: Any] = [
      "model": llm.modelID,
      "messages": [["role": "system", "content": system]] + outboundMessages(),
      "tools": tools.map { tool in
        [
          "type": "function",
          "function": [
            "name": tool.rawValue,
            "description": toolDescriptions[tool] ?? tool.summary,
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
    ]
    let outputIsReserved = try reserveOutput(in: &body, isStreaming: onText != nil)
    request.httpBody = try requestBody(body)

    try runBudget.reserveRequest(bytes: request.httpBody?.count ?? 0)
    let decoded: [String: Any]
    if let onText {
      decoded = try await CloudTurnStreaming.response(for: request, provider: .chatCompletions, onText: onText, sessionConfiguration: sessionConfiguration)
    } else {
      decoded = try await boundedResponse(for: request)
    }
    try settleOutput(decoded, reserved: outputIsReserved)
    try runBudget.acceptResponse(bytes: JSONSerialization.data(withJSONObject: decoded).count)
    guard let choices = decoded["choices"] as? [[String: Any]],
          var assistant = choices.first?["message"] as? [String: Any] else { throw AIAnswerFailure.server }
    let turn = try CloudAgentTurnDecoder.chatCompletions(decoded)
    // Keep provider extras (including reasoning/signatures) for the next request.
    assistant["role"] = "assistant"
    messages.append(assistant)
    return turn
  }
}
