import Foundation

/// Asks a provider's API for an answer using the person's own key.
enum CloudAIService {
  static func answer(
    question: String,
    scopeLabel: String,
    context: String,
    history: String,
    llm: LLMSelection,
    onText: (@MainActor (String) -> Void)? = nil
  ) async -> AIAnswerResult {
    let system = """
    あなたは会議の記録を要約して答えるアシスタントです。短い日本語で、与えられた記録だけに沿って答えます。
    記録をもとにした文の末尾には、その記録の番号を【資料1】の形で付けます。与えられた番号だけを使い、記録にない内容には付けません。

    \(ReadabilityGuide.rules)
    """
    let user = AIAnswerPrompt.text(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: history
    )
    if let onText { return await streamedAnswer(system: system, user: user, llm: llm, onText: onText) }
    return await complete(system: system, user: user, llm: llm)
  }

  @MainActor
  private static func streamedAnswer(system: String, user: String, llm: LLMSelection,
                                     onText: @escaping @MainActor (String) -> Void) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }
    let anthropicAPI = llm.provider.usesAnthropicAPI
    var request = URLRequest(url: anthropicAPI ? LLMProvider.anthropic.baseURL.appendingPathComponent("messages") : llm.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["model": llm.modelID, "messages": [["role": "user", "content": user]]]
    if anthropicAPI {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
      body["system"] = system
      body["max_tokens"] = 16_000
      if llm.modelID == "claude-opus-5" || llm.modelID == "claude-fable-5-1" {
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        body["fallbacks"] = "default"
      }
    } else {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      if llm.provider == .openRouter { request.setValue("Memora", forHTTPHeaderField: "X-Title") }
      body["messages"] = [["role": "system", "content": system], ["role": "user", "content": user]]
    }
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let response = try await CloudTurnStreaming.response(for: request, provider: anthropicAPI ? .anthropic : .chatCompletions, onText: onText)
      let text: String
      if anthropicAPI {
        guard response["stop_reason"] as? String != "refusal" else { throw AIAnswerFailure.refused }
        text = (response["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
      } else {
        text = ((response["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
      }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? .failure(.empty) : .answer(trimmed)
    } catch let reason as AIAnswerFailure { return .failure(reason) }
    catch is CancellationError { return .failure(.cancelled) }
    catch let error as URLError { return .failure(failure(for: error)) }
    catch { return .failure(.network) }
  }

  /// Sends one system and user prompt to the chosen provider. Ask AI and the
  /// summarizer share it, each with its own instructions.
  static func complete(system: String, user: String, llm: LLMSelection, maximumOutputTokens: Int? = nil) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }

    do {
      let text = if llm.provider.usesAnthropicAPI {
        try await anthropic(system: system, user: user, model: llm.modelID, key: key, maximumOutputTokens: maximumOutputTokens)
      } else {
        try await chatCompletions(system: system, user: user, llm: llm, key: key, maximumOutputTokens: maximumOutputTokens)
      }
      return .answer(text)
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      return .failure(failure(for: error))
    } catch {
      return .failure(.network)
    }
  }

  static func failure(for error: URLError) -> AIAnswerFailure {
    switch error.code {
    case .cancelled: .cancelled
    case .timedOut: .timedOut
    case .networkConnectionLost: .connectionLost
    default: .network
    }
  }

  /// Streams the answer instead of waiting for it whole. A long summary takes
  /// minutes to write; streamed, the connection carries text the whole time, so
  /// no idle timeout cuts it off, and `onProgress` can say how much has come in.
  /// An answer cut off at the provider's length limit is continued, up to a few
  /// times, rather than returned half-written.
  static func completeStreaming(
    system: String,
    user: String,
    llm: LLMSelection,
    onProgress: @escaping @MainActor (Int) -> Void
  ) async -> AIAnswerResult {
    // The Anthropic path has its own long timeout and a generous token cap.
    guard !llm.provider.usesAnthropicAPI else {
      return await complete(system: system, user: user, llm: llm)
    }
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }

    var messages: [[String: String]] = [
      ["role": "system", "content": system],
      ["role": "user", "content": user]
    ]
    var answer = ""
    do {
      for _ in 0..<maxContinuations {
        let alreadyWritten = answer.count
        let part = try await streamChatCompletion(messages: messages, llm: llm, key: key) { count in
          onProgress(alreadyWritten + count)
        }
        answer += part.text
        guard part.wasCutOff else { break }
        messages.append(["role": "assistant", "content": answer])
        messages.append(["role": "user", "content": "出力が途中で切れました。直前の出力の続きから、重複させずにそのまま書き続けてください。"])
      }
      let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? .failure(.empty) : .answer(text)
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      return .failure(failure(for: error))
    } catch {
      return .failure(.network)
    }
  }

  private static let maxContinuations = 4

  private static func streamChatCompletion(
    messages: [[String: String]],
    llm: LLMSelection,
    key: String,
    onProgress: @escaping @MainActor (Int) -> Void
  ) async throws -> (text: String, wasCutOff: Bool) {
    var request = URLRequest(url: llm.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    // The gap allowed between two pieces of the stream, not the whole answer.
    // Reasoning models can think quietly for a while before the first word.
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    if llm.provider == .openRouter {
      request.setValue("Memora", forHTTPHeaderField: "X-Title")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": llm.modelID,
      "messages": messages,
      "stream": true
    ] as [String: Any])

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    try validate(response)

    var text = ""
    var finishReason: String?
    var lastReported = 0
    for try await line in bytes.lines {
      // Blank lines and ": keep-alive" comments only keep the connection open.
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" { break }
      guard let data = payload.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else { continue }
      if chunk.error != nil { throw AIAnswerFailure.server }
      for choice in chunk.choices ?? [] {
        if let piece = choice.delta?.content { text += piece }
        if let reason = choice.finishReason { finishReason = reason }
      }
      if text.count - lastReported >= 400 {
        lastReported = text.count
        await onProgress(text.count)
      }
    }
    return (text, finishReason == "length")
  }

  /// The OpenAI chat-completions shape, which every non-Anthropic provider here
  /// accepts. No temperature or token cap is sent: newer reasoning models
  /// reject both, and the defaults suit summaries.
  private static func chatCompletions(
    system: String,
    user: String,
    llm: LLMSelection,
    key: String,
    maximumOutputTokens: Int? = nil
  ) async throws -> String {
    var request = URLRequest(url: llm.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = 180
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    if llm.provider == .openRouter {
      request.setValue("Memora", forHTTPHeaderField: "X-Title")
    }
    var body: [String: Any] = [
      "model": llm.modelID,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user]
      ]
    ]
    if let cap = maximumOutputTokens {
      guard (1...16_000).contains(cap) else { throw AIAnswerFailure.executionLimit }
      body[llm.provider == .openAI ? "max_completion_tokens" : "max_tokens"] = cap
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response)
    let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    if maximumOutputTokens != nil, decoded.choices.first?.finishReason == "length" { throw AIAnswerFailure.executionLimit }
    let text = decoded.choices.first?.message.content?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else { throw AIAnswerFailure.empty }
    return text
  }

  private static func anthropic(system: String, user: String, model: String, key: String, maximumOutputTokens: Int? = nil) async throws -> String {
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
      "max_tokens": maximumOutputTokens ?? 16_000,
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
    if maximumOutputTokens != nil, decoded.stopReason == "max_tokens" { throw AIAnswerFailure.executionLimit }
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
    MemoraCreditMeter.observe(response)
    switch http.statusCode {
    case 200..<300:
      return
    case 401, 403:
      throw AIAnswerFailure.unauthorized
    case 404:
      throw AIAnswerFailure.modelUnavailable
    case 402:
      throw AIAnswerFailure.outOfCredits
    case 429:
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
    var finishReason: String?
    enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" }
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

/// One piece of a streamed chat-completions answer.
private struct ChatCompletionChunk: Decodable {
  struct Choice: Decodable {
    struct Delta: Decodable { var content: String? }
    var delta: Delta?
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
      case delta
      case finishReason = "finish_reason"
    }
  }
  struct StreamError: Decodable { var message: String? }
  var choices: [Choice]?
  var error: StreamError?
}
