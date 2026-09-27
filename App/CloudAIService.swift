import Foundation

/// Asks a provider's API for an answer using the person's own key.
enum CloudAIService {
  static func answer(
    question: String,
    scopeLabel: String,
    context: String,
    history: String,
    llm: LLMSelection
  ) async -> AIAnswerResult {
    let system = "あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、与えられた記録だけに沿って答えます。"
    let user = AIAnswerPrompt.text(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: history
    )
    return await complete(system: system, user: user, llm: llm)
  }

  /// Sends one system and user prompt to the chosen provider. Ask AI and the
  /// summarizer share it, each with its own instructions.
  static func complete(system: String, user: String, llm: LLMSelection) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.provider.keychainAccount), !key.isEmpty else {
      return .failure(.missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }

    do {
      let text = if llm.provider.usesAnthropicAPI {
        try await anthropic(system: system, user: user, model: llm.modelID, key: key)
      } else {
        try await chatCompletions(system: system, user: user, llm: llm, key: key)
      }
      return .answer(text)
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      return .failure(error.code == .cancelled ? .cancelled : .network)
    } catch {
      return .failure(.network)
    }
  }

  /// The OpenAI chat-completions shape, which every non-Anthropic provider here
  /// accepts. No temperature or token cap is sent: newer reasoning models
  /// reject both, and the defaults suit summaries.
  private static func chatCompletions(
    system: String,
    user: String,
    llm: LLMSelection,
    key: String
  ) async throws -> String {
    var request = URLRequest(url: llm.provider.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    if llm.provider == .openRouter {
      request.setValue("Memora", forHTTPHeaderField: "X-Title")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": llm.modelID,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
      ]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    let text = decoded.choices.first?.message.content?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else { throw AIAnswerFailure.empty }
    return text
  }

  private static func anthropic(system: String, user: String, model: String, key: String) async throws -> String {
    var request = URLRequest(url: LLMProvider.anthropic.baseURL.appendingPathComponent("messages"))
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    var body: [String: Any] = [
      "model": model,
      // Current models think before answering, and thinking counts against
      // this cap, so a small cap cut summaries off mid-sentence.
      "max_tokens": 16_000,
      "system": system,
      "messages": [["role": "user", "content": user]]
    ]
    // These models may decline a request on a safety classifier; a server-side
    // fallback lets another model answer instead of returning nothing.
    if model == "claude-opus-5" || model == "claude-fable-5-1" {
      request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
      body["fallbacks"] = "default"
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
    if decoded.stopReason == "refusal" { throw AIAnswerFailure.refused }
    // Thinking blocks come first and carry no text; only text blocks are the
    // answer.
    let text = decoded.content
      .filter { $0.type == "text" }
      .compactMap(\.text)
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw AIAnswerFailure.empty }
    return text
  }

  /// Turns the provider's status into the reason it failed, so a wrong key, a
  /// model that no longer exists, and a busy API are not reported alike.
  static func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw AIAnswerFailure.network }
    switch http.statusCode {
    case 200..<300:
      return
    case 401, 403:
      throw AIAnswerFailure.unauthorized
    case 404:
      throw AIAnswerFailure.modelUnavailable
    case 402, 429:
      throw AIAnswerFailure.rateLimited
    default:
      throw AIAnswerFailure.server
    }
  }
}

private struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable { var content: String? }
    var message: Message
  }
  var choices: [Choice]
}

private struct AnthropicResponse: Decodable {
  struct Block: Decodable {
    var type: String
    var text: String?
  }
  var content: [Block]
  var stopReason: String?

  enum CodingKeys: String, CodingKey {
    case content
    case stopReason = "stop_reason"
  }
}
