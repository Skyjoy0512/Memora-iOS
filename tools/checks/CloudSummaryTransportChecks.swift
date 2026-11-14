import Foundation

/// Runs the actual summary HTTP/SSE path with fail-closed, offline responses.
@MainActor
enum CloudSummaryTransportChecks {
  typealias Wire = CloudSessionFixtureProtocol
  typealias Response = CloudSessionFixtureResponse

  static func run() async throws {
    for provider in [LLMProvider.openAI, .anthropic, .deepSeek] {
      for streaming in [false, true] {
        let text = "## 確認事項\n承認前には公開しない。👨‍👩‍👧‍👦\n"
        Wire.state.reset(try [reply(provider, text: text, streaming: streaming)])
        var counts: [Int] = []
        let result = await complete(provider) { counts.append($0) }
        check(result, .answer(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        precondition(!counts.isEmpty && counts == counts.sorted() && counts.last == text.count)
        try validateRequest(Wire.state.requests[0], provider: provider)
        Wire.state.assertConsumed(1)

        let tool = AgentToolCall(id: "never-execute", name: "draft_email", arguments: [:])
        Wire.state.reset(try [streaming ? Response.sse(provider: provider, calls: [tool], text: text) :
          Response.json(provider: provider, calls: [tool], text: text)])
        check(await complete(provider), .failure(.server))
        Wire.state.assertConsumed(1)

        Wire.state.reset(try [reply(provider, text: text, streaming: streaming, finish: "refusal")])
        check(await complete(provider), .failure(.refused))
        Wire.state.assertConsumed(1)

        Wire.state.reset(try [reply(provider, text: "", streaming: streaming)])
        check(await complete(provider), .failure(.empty))
        Wire.state.assertConsumed(1)
        for (finish, failure) in [("insufficient_system_resource", AIAnswerFailure.providerUnavailable), ("aborted", .providerInterrupted)] {
          Wire.state.reset(try [reply(provider, text: "途中の文章", streaming: streaming, finish: finish)])
          check(await complete(provider), .failure(failure))
          Wire.state.assertConsumed(1)
        }
      }

      // Even a finish_reason without its transport terminator is not complete.
      Wire.state.reset(try [Response.sse(provider: provider, text: "保存してはいけない途中の文章", terminated: false)])
      check(await complete(provider), .failure(.connectionLost))
      Wire.state.assertConsumed(1)
      try await limitChecks(provider)
      try await cancellationChecks(provider)

      for (status, reason) in [(401, AIAnswerFailure.unauthorized), (403, .unauthorized),
        (402, .outOfCredits), (429, .rateLimited), (500, .server), (408, .providerTimedOut),
        (502, .providerUnavailable), (503, .providerUnavailable), (504, .providerTimedOut)] {
        Wire.state.reset([.init(data: Data(), status: status)])
        check(await complete(provider), .failure(reason))
        Wire.state.assertConsumed(1)
      }
      for (code, reason) in [(URLError.Code.timedOut, AIAnswerFailure.timedOut),
        (.networkConnectionLost, .connectionLost), (.cancelled, .cancelled)] {
        Wire.state.reset([.init(data: Data(), error: URLError(code))])
        check(await complete(provider), .failure(reason))
        Wire.state.assertConsumed(1)
      }
    }
    try await continuationChecks()
    try await processingModeChecks()
    try completedJSONChecks()
    for streaming in [false, true] {
      let diagnostics = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "fixture", model: "fixture", characters: 1, segments: 1)
      Wire.state.reset(try [reply(.openAI, text: "一回目", streaming: streaming), reply(.openAI, text: "二回目", streaming: streaming)])
      await SummaryDiagnostics.$current.withValue(diagnostics) {
        check(await complete(.openAI), .answer("一回目"))
        check(await complete(.openAI), .answer("二回目"))
      }
      let ids = diagnostics.events.filter { $0.stage == .request }.compactMap(\.requestID)
      precondition(ids.count == 2 && Set(ids).count == 2)
      for id in ids {
        precondition(diagnostics.events.filter { $0.requestID == id && $0.stage == .firstToken }.count == 1)
        precondition(diagnostics.events.filter { $0.requestID == id && $0.stage == .lastToken }.count == 1)
        precondition(diagnostics.events.contains { $0.requestID == id && $0.reason == "stop" })
      }
      Wire.state.assertConsumed(2)
    }
    print("CloudSummaryTransportChecks: passed (production summary → URLSession → bounded SSE/JSON → terminal text validation; both APIs, EOF/refusal/tools/limits/cancel/HTTP failures, bounded continuations; no keys/network/paid API)")
  }

  static func processingModeChecks() async throws {
    Wire.state.reset([])
    check(await CloudAIService.completeStreaming(system: "fixture", user: "fixture",
      llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"),
      sessionConfiguration: CloudSessionChecks.configuration(), processingMode: .fast,
      authorize: { false }, onProgress: { _ in }), .failure(.cancelled))
    Wire.state.assertConsumed(0)
    Wire.state.reset(try [reply(.deepSeek, text: "途中の本文", finish: "length")])
    var authorized = true
    check(await CloudAIService.completeStreaming(system: "fixture", user: "fixture",
      llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"),
      sessionConfiguration: CloudSessionChecks.configuration(), processingMode: .fast,
      authorize: { authorized }, onProgress: { _ in authorized = false }), .failure(.cancelled))
    Wire.state.assertConsumed(1)
    for provider in LLMProvider.allCases {
      for model in ["deepseek-flash", "deepseek-v4-pro", "deepseek-reasoner", "registered-unknown"] {
        for mode in SummaryProcessingMode.allCases {
          for custom in [false, true] {
            let llm = LLMSelection(provider: provider, modelID: model,
              endpoint: custom ? URL(string: "https://offline.invalid/v1") : nil,
              credentialAccount: "ai.deepSeek")
            Wire.state.reset(try [reply(provider, text: "決定は条件付き。予算150万円、期限は未定。")])
            let result = await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
              sessionConfiguration: CloudSessionChecks.configuration(), processingMode: mode, onProgress: { _ in })
            check(result, .answer("決定は条件付き。予算150万円、期限は未定。"))
            let body = try CloudSessionChecks.body(Wire.state.requests[0])
            precondition(body["fallbacks"] == nil && Wire.state.requests[0].value(forHTTPHeaderField: "anthropic-beta") == nil)
            precondition(Wire.state.requests[0].url == llm.baseURL.appendingPathComponent(provider.usesAnthropicAPI ? "messages" : "chat/completions"))
            let controlled = provider == .deepSeek && !custom && ["deepseek-flash", "deepseek-v4-pro"].contains(model) && mode != .balanced
            if controlled {
              precondition((body["thinking"] as? [String: String])?["type"] == (mode == .fast ? "disabled" : "enabled"))
              precondition(body["max_tokens"] as? Int == 65_536)
              precondition(body["reasoning_effort"] as? String == (mode == .accurate ? "high" : nil))
            } else {
              precondition(body["thinking"] == nil && body["reasoning_effort"] == nil, "Provider flag leaked to an unverified route")
            }
            let expectedWidth = SummaryGenerationPolicy.parallelism(capabilities: ModelCapabilityRegistry.capabilities(for: llm),
              lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermalState: ProcessInfo.processInfo.thermalState.rawValue)
            precondition(SummaryGenerationPolicy.parallelParts(mode, llm: llm) == expectedWidth)
            Wire.state.assertConsumed(1)
          }
        }
      }
    }
  }

  static func completedJSONChecks() throws {
    for provider in [LLMProvider.openAI, .anthropic] {
      let format: CloudStreamAccumulator.Provider = provider.usesAnthropicAPI ? .anthropic : .chatCompletions
      let valid = try Response.json(provider: provider, text: "検証用の回答")
      let text = try CloudAIService.completedText(valid.data, provider: format)
      precondition(text == "検証用の回答")
      for (reason, expected) in [(provider.usesAnthropicAPI ? "max_tokens" : "length", AIAnswerFailure.executionLimit),
        ("refusal", .refused), ("unknown", .server)] {
        let invalid = try Response.json(provider: provider, finish: reason)
        do { _ = try CloudAIService.completedText(invalid.data, provider: format); preconditionFailure("Invalid JSON completion accepted") }
        catch let failure as AIAnswerFailure { precondition(failure == expected) }
      }
    }
  }

  static func complete(_ provider: LLMProvider, onProgress: @escaping @MainActor (Int) -> Void = { _ in }) async -> AIAnswerResult {
    await CloudAIService.completeStreaming(system: "架空の検査用", user: "要約してください",
      llm: LLMSelection(provider: provider, modelID: "offline-fixture-model"),
      sessionConfiguration: CloudSessionChecks.configuration(), onProgress: onProgress)
  }

  static func reply(_ provider: LLMProvider, text: String, streaming: Bool = true, finish: String? = nil) throws -> Wire.Reply {
    try streaming ? Response.sse(provider: provider, text: text, finish: finish) :
      Response.json(provider: provider, text: text, finish: finish)
  }

  static func limitChecks(_ provider: LLMProvider) async throws {
    let reason = provider.usesAnthropicAPI ? "max_tokens" : "length"
    let limit = provider.usesAnthropicAPI ? 1 : 4
    Wire.state.reset(try (0..<limit).map { _ in try reply(provider, text: "続きが必要な文章", finish: reason) })
    check(await complete(provider), .failure(.executionLimit))
    Wire.state.assertConsumed(limit)
    // Agent tools must still reject length-limited turns in their default mode.
    let response = try Response.json(provider: provider, text: "途中", finish: reason)
    let object = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
    do {
      _ = try provider.usesAnthropicAPI ? CloudAgentTurnDecoder.anthropic(object) : CloudAgentTurnDecoder.chatCompletions(object)
      preconditionFailure("Summary continuation policy escaped to agent tools")
    } catch AIAnswerFailure.executionLimit {}
  }

  static func continuationChecks() async throws {
    let parts = ["## 方針\n承認を待つ。\n", "\n- 条件：個人情報を除く\n", "- 公開日は未定。"]
    for streaming in [false, true] {
      Wire.state.reset(try parts.enumerated().map { index, text in
        try reply(.openAI, text: text, streaming: streaming, finish: index < 2 ? "length" : "stop")
      })
      check(await complete(.openAI), .answer(parts.joined()))
      let messages = try CloudSessionChecks.body(Wire.state.requests[2])["messages"] as! [[String: String]]
      precondition(messages.filter { $0["role"] == "assistant" }.compactMap { $0["content"] } == Array(parts.prefix(2)))
      Wire.state.assertConsumed(3)
    }
    Wire.state.reset(try [reply(.openAI, text: parts[0], finish: "length"),
      Response.sse(provider: .openAI, text: "不完全な続き", terminated: false)])
    check(await complete(.openAI), .failure(.connectionLost))
    Wire.state.assertConsumed(2)
  }

  static func cancellationChecks(_ provider: LLMProvider) async throws {
    var held = try reply(provider, text: "まだ完了しない")
    held.isSuspended = true
    Wire.state.reset([held])
    let work = Task { await complete(provider) }
    let start = ContinuousClock.now
    while !Wire.state.isSuspended {
      precondition(start.duration(to: .now) < .seconds(5))
      try await Task.sleep(for: .milliseconds(10))
    }
    work.cancel()
    check(await work.value, .failure(.cancelled))
    Wire.state.assertConsumed(1)

    for streaming in [false, true] {
      Wire.state.reset(try [reply(provider, text: "続きの申請より前に停止", streaming: streaming,
        finish: provider.usesAnthropicAPI ? "max_tokens" : "length")])
      let stopped = Task { await complete(provider) { _ in withUnsafeCurrentTask { $0?.cancel() } } }
      check(await stopped.value, .failure(.cancelled))
      Wire.state.assertConsumed(1)
    }
  }

  static func validateRequest(_ request: URLRequest, provider: LLMProvider) throws {
    let body = try CloudSessionChecks.body(request)
    precondition(body["stream"] as? Bool == true && body["tools"] == nil)
    precondition(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    if provider.usesAnthropicAPI {
      precondition(request.url?.path == "/v1/messages" && body["max_tokens"] as? Int == 16_000)
      precondition(request.value(forHTTPHeaderField: "x-api-key") == "offline-fixture-key")
      precondition(body["system"] as? String == "架空の検査用")
    } else {
      precondition(request.url?.path == (provider == .deepSeek ? "/chat/completions" : "/v1/chat/completions"))
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-fixture-key")
    }
  }

  private static func check(_ actual: AIAnswerResult, _ expected: AIAnswerResult) {
    precondition(actual.text == expected.text && actual.failure == expected.failure,
      "Expected \(expected), received \(actual)")
  }
}
