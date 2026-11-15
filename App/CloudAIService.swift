import Foundation

/// Asks a provider's API for an answer using the person's own key.
enum CloudAIService {
  static func answer(
    question: String,
    scopeLabel: String,
    context: String,
    history: String,
    llm: LLMSelection,
    onText: (@MainActor (String) -> Void)? = nil,
    authorize: (@MainActor () -> Bool)? = nil
  ) async -> AIAnswerResult {
    let system = """
    \(AIAnswerPrompt.grounding)
    記録をもとにした文の末尾には、その記録の番号を【資料1】の形で付けます。与えられた番号だけを使い、記録にない内容には付けません。

    \(ReadabilityGuide.rules)
    """
    let user = AIAnswerPrompt.text(
      question: question,
      scopeLabel: scopeLabel,
      context: context,
      history: history
    )
    if let onText { return await streamedAnswer(system: system, user: user, llm: llm, onText: onText, authorize: authorize) }
    return await complete(system: system, user: user, llm: llm, authorize: authorize)
  }

  @MainActor
  private static func streamedAnswer(system: String, user: String, llm: LLMSelection,
                                     onText: @escaping @MainActor (String) -> Void, authorize: (@MainActor () -> Bool)?) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }
    let anthropicAPI = llm.provider.usesAnthropicAPI
    do {
      let messages = anthropicAPI ? [["role": "user", "content": user]] :
        [["role": "system", "content": system], ["role": "user", "content": user]]
      let request = try streamingRequest(system: system, messages: messages, llm: llm, key: key)
      let response = try await CloudTurnStreaming.response(for: request, provider: anthropicAPI ? .anthropic : .chatCompletions, onText: onText,
        authorize: { KeychainStore.string(forKey: llm.keychainAccount) == key && (authorize?() ?? true) })
      let part = try CloudSummaryResponse(response, provider: anthropicAPI ? .anthropic : .chatCompletions)
      guard !part.wasCutOff else { throw AIAnswerFailure.executionLimit }
      return .answer(part.text.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch let reason as AIAnswerFailure { return .failure(reason) }
    catch is CancellationError { return .failure(.cancelled) }
    catch let error as URLError { return .failure(failure(for: error)) }
    catch { return .failure(.network) }
  }

  /// Sends one system and user prompt to the chosen provider. Ask AI and the
  /// summarizer share it, each with its own instructions.
  static func complete(system: String, user: String, llm: LLMSelection, maximumOutputTokens: Int? = nil,
    sessionConfiguration: URLSessionConfiguration = .ephemeral, admission: SummaryRequestAdmission = .shared,
    authorize: (@MainActor () -> Bool)? = nil) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }

    do {
      let text = if llm.provider.usesAnthropicAPI {
        try await anthropic(system: system, user: user, llm: llm, key: key, maximumOutputTokens: maximumOutputTokens, sessionConfiguration: sessionConfiguration, admission: admission, authorize: authorize)
      } else {
        try await chatCompletions(system: system, user: user, llm: llm, key: key, maximumOutputTokens: maximumOutputTokens, sessionConfiguration: sessionConfiguration, admission: admission, authorize: authorize)
      }
      return .answer(text)
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      SummaryDiagnostics.current?.record(.failed, code: error.errorCode)
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

  /// A transport EOF is not a completed summary. Continue only an explicitly
  /// length-limited, terminated text response, never a disconnected request.
  static func completeStreaming(
    system: String,
    user: String,
    llm: LLMSelection,
    sessionConfiguration: URLSessionConfiguration = .ephemeral,
    admission: SummaryRequestAdmission = .shared,
    transport: CloudHTTPTransport? = nil,
    processingMode: SummaryProcessingMode = .balanced,
    authorize: (@MainActor () -> Bool)? = nil,
    onActivity: (@MainActor () -> Void)? = nil,
    onProgress: @escaping @MainActor (Int) -> Void
  ) async -> AIAnswerResult {
    guard let key = KeychainStore.string(forKey: llm.keychainAccount), !key.isEmpty else {
      return .failure(llm.isMemoraIntelligence ? .serviceNotConnected : .missingKey)
    }
    guard !llm.modelID.isEmpty else { return .failure(.modelUnavailable) }

    let endpoint = llm.baseURL.appendingPathComponent(llm.provider.usesAnthropicAPI ? "messages" : "chat/completions")
    let receiver = transport ?? CloudHTTPTransport(endpoint: endpoint, configuration: sessionConfiguration,
      summaryConcurrency: SummaryGenerationPolicy.parallelParts(processingMode, llm: llm), admission: admission,
      requestsPerMinute: ModelCapabilityRegistry.capabilities(for: llm).requestsPerMinute,
      tokensPerMinute: ModelCapabilityRegistry.capabilities(for: llm).tokensPerMinute)
    defer { if transport == nil { receiver.invalidate() } }
    let anthropicAPI = llm.provider.usesAnthropicAPI
    let provider: CloudStreamAccumulator.Provider = anthropicAPI ? .anthropic : .chatCompletions
    var messages = anthropicAPI ? [["role": "user", "content": user]] :
      [["role": "system", "content": system], ["role": "user", "content": user]]
    // Preserve the old request ceilings: no new automatic Anthropic charges.
    let requestLimit = anthropicAPI ? 1 : maxContinuations
    var answer = ""
    do {
      for attempt in 0..<requestLimit {
        try Task.checkCancellation()
        if let authorize, !(await authorize()) { throw AIAnswerFailure.cancelled }
        try Task.checkCancellation()
        let alreadyWritten = answer.count
        let request = try streamingRequest(system: system, messages: messages, llm: llm, key: key, processingMode: processingMode)
        let response = try await SummaryDiagnostics.$isContinuation.withValue(attempt > 0) {
          try await CloudTurnStreaming.response(for: request, provider: provider,
            onText: { text in onProgress(alreadyWritten + text.count) },
            sessionConfiguration: sessionConfiguration, transport: receiver, onActivity: onActivity,
            responseKind: .textCompletion, encoding: .streamAlreadyConfigured, authorize: authorize)
        }
        try Task.checkCancellation()
        let part = try CloudSummaryResponse(response, provider: provider)
        answer += part.text
        // Also publish short/JSON responses, so access-change cancellation runs
        // before another billable continuation could be submitted.
        await onProgress(answer.count)
        try Task.checkCancellation()
        guard part.wasCutOff else { return .answer(answer.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard attempt + 1 < requestLimit else { throw AIAnswerFailure.executionLimit }
        messages.append(["role": "assistant", "content": part.text])
        messages.append(["role": "user", "content": "出力が途中で切れました。直前の出力の続きから、重複させずにそのまま書き続けてください。"])
      }
      return .failure(.executionLimit)
    } catch let failure as AIAnswerFailure {
      return .failure(failure)
    } catch is CancellationError {
      return .failure(.cancelled)
    } catch let error as URLError {
      SummaryDiagnostics.current?.record(.failed, code: error.errorCode)
      return .failure(failure(for: error))
    } catch {
      return .failure(.network)
    }
  }

  private static let maxContinuations = 4

  private static func streamingRequest(
    system: String,
    messages: [[String: String]],
    llm: LLMSelection,
    key: String,
    processingMode: SummaryProcessingMode = .balanced
  ) throws -> URLRequest {
    let anthropicAPI = llm.provider.usesAnthropicAPI
    var request = URLRequest(url: anthropicAPI ? llm.baseURL.appendingPathComponent("messages") : llm.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    // The gap allowed between two pieces of the stream, not the whole answer.
    // Reasoning models can think quietly for a while before the first word.
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["model": llm.modelID, "messages": messages, "stream": true]
    if anthropicAPI {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
      body["system"] = system
      body["max_tokens"] = 16_000
    } else {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      if llm.provider == .openRouter { request.setValue("Memora", forHTTPHeaderField: "X-Title") }
    }
    SummaryGenerationPolicy.apply(processingMode, llm: llm, to: &body)
    AgentGenerationPolicy.resolve(provider: llm.provider, modelID: llm.modelID,
      hasCustomEndpoint: llm.endpoint != nil || llm.isMemoraIntelligence)?.applyStreamingUsage(to: &body, isStreaming: true)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  /// The OpenAI chat-completions shape, which every non-Anthropic provider here
  /// accepts. Output caps are opt-in for bounded research; unsupported providers
  /// fail without a second chargeable request. Summary defaults remain unchanged.
  private static func chatCompletions(
    system: String,
    user: String,
    llm: LLMSelection,
    key: String,
    maximumOutputTokens: Int? = nil, sessionConfiguration: URLSessionConfiguration,
    admission: SummaryRequestAdmission, authorize: (@MainActor () -> Bool)?
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

    let receiver = CloudHTTPTransport(endpoint: request.url!, configuration: sessionConfiguration, admission: admission)
    defer { receiver.invalidate() }
    let (data, response) = try await receiver.data(for: request) {
      KeychainStore.string(forKey: llm.keychainAccount) == key && (authorize?() ?? true)
    }
    try validate(response)
    return try completedText(data, provider: .chatCompletions)
  }

  private static func anthropic(system: String, user: String, llm: LLMSelection, key: String, maximumOutputTokens: Int? = nil,
    sessionConfiguration: URLSessionConfiguration, admission: SummaryRequestAdmission,
    authorize: (@MainActor () -> Bool)?) async throws -> String {
    var request = URLRequest(url: llm.baseURL.appendingPathComponent("messages"))
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let body: [String: Any] = [
      "model": llm.modelID,
      // Current models think before answering, and thinking counts against
      // this cap, so a small cap cut summaries off mid-sentence.
      "max_tokens": maximumOutputTokens ?? 16_000,
      "system": system,
      "messages": [["role": "user", "content": user]]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let receiver = CloudHTTPTransport(endpoint: request.url!, configuration: sessionConfiguration, admission: admission)
    defer { receiver.invalidate() }
    let (data, response) = try await receiver.data(for: request) {
      KeychainStore.string(forKey: llm.keychainAccount) == key && (authorize?() ?? true)
    }
    try validate(response)
    return try completedText(data, provider: .anthropic)
  }

  static func completedText(_ data: Data, provider: CloudStreamAccumulator.Provider) throws -> String {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
    let result = try CloudSummaryResponse(object, provider: provider)
    guard !result.wasCutOff else { throw AIAnswerFailure.executionLimit }
    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    case 408, 504:
      throw AIAnswerFailure.providerTimedOut
    case 502, 503:
      throw AIAnswerFailure.providerUnavailable
    default:
      throw AIAnswerFailure.server
    }
  }
}
