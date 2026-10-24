import Foundation

/// Runs the actual summary HTTP/SSE path with fail-closed, offline responses.
@MainActor
enum CloudSummaryTransportChecks {
  typealias Wire = CloudSessionFixtureProtocol
  typealias Response = CloudSessionFixtureResponse

  static func run() async throws {
    for provider in [LLMProvider.openAI, .anthropic] {
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
      }

      // Even a finish_reason without its transport terminator is not complete.
      Wire.state.reset(try [Response.sse(provider: provider, text: "保存してはいけない途中の文章", terminated: false)])
      check(await complete(provider), .failure(.connectionLost))
      Wire.state.assertConsumed(1)
      try await limitChecks(provider)
      try await cancellationChecks(provider)

      for (status, reason) in [(401, AIAnswerFailure.unauthorized), (403, .unauthorized),
        (402, .outOfCredits), (429, .rateLimited), (500, .server)] {
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
    print("CloudSummaryTransportChecks: passed (production summary → URLSession → bounded SSE/JSON → terminal text validation; both APIs, EOF/refusal/tools/limits/cancel/HTTP failures, bounded continuations; no keys/network/paid API)")
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
      precondition(request.url?.path == "/v1/chat/completions")
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-fixture-key")
    }
  }

  private static func check(_ actual: AIAnswerResult, _ expected: AIAnswerResult) {
    precondition(actual.text == expected.text && actual.failure == expected.failure,
      "Expected \(expected), received \(actual)")
  }
}
