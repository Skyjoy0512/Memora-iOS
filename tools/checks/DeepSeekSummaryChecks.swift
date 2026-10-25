import Foundation

@main
enum DeepSeekSummaryChecks {
  @MainActor static func main() async throws {
    try buffering()
    // Realistic Chat Completions framing: the same envelope repeats for each
    // tiny inference delta. Nothing here is actual private model reasoning.
    let prefix = #"{"id":"offline-deepseek-trace","object":"chat.completion.chunk","created":0,"model":"deepseek-v4-pro","system_fingerprint":"fixture","choices":[{"index":0,"delta":{"reasoning_content":"fixture"},"finish_reason":null,"logprobs":null}]}"#
    let reasoning = String(repeating: "data: \(prefix)\n\n", count: 9_000)
    let final = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"## 要約\\n条件を維持する。\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    let bytes = Data((reasoning + final).utf8)
    print("Synthetic DeepSeek SSE bytes=\(bytes.count); 9000 reasoning-only chunks before answer")
    let start = ContinuousClock.now
    var tick = 0
    var activity = 0
    var publications: [String] = []
    let diagnostics = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "deepSeek", model: "fixture", characters: 10, segments: 1)
      let response = try await SummaryDiagnostics.$current.withValue(diagnostics) {
        try await CloudTurnStreamReader.response(from: Bytes(data: bytes), provider: .chatCompletions,
        responseKind: .textCompletion, now: {
          defer { tick += 1 }
          return start.advanced(by: .milliseconds(tick * 6))
        }, onActivity: {
          activity += 1
          if tick < 9_000 { precondition(!diagnostics.events.contains { $0.stage == .firstToken }, "Reasoning was mislabeled as visible text") }
        }, onText: { publications.append($0) })
      }
      let result = try CloudSummaryResponse(response, provider: .chatCompletions)
      precondition(result.text == "## 要約\n条件を維持する。")
      let message = ((response["choices"] as! [[String: Any]])[0]["message"] as! [String: Any])
      precondition(message["reasoning_content"] == nil, "Summary retained private inference text it never uses")
      precondition(activity > 50 && publications == [result.text], "Real inference activity was hidden or private output was published")
      precondition(diagnostics.events.filter { $0.stage == .firstReasoning }.count == 1)
      precondition(diagnostics.events.filter { $0.stage == .firstToken }.count == 1)
      precondition(diagnostics.events.firstIndex { $0.stage == .firstReasoning }! < diagnostics.events.firstIndex { $0.stage == .firstToken }!)
      var bounded = CloudSSEEventDecoder(maximumBytes: 1_024, maximumBufferedBytes: 16)
      for _ in 0..<16 { _ = try bounded.consume(120) }
      do { _ = try bounded.consume(120); preconditionFailure("Oversized SSE event retained") }
      catch AIAnswerFailure.executionLimit {}
      print("DeepSeekSummaryChecks: PASS; bounded summary wire budget, final document intact, no reasoning retained")
  }

  static func buffering() throws {
    func json(_ object: [String: Any]) throws -> String {
      String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    var chat = CloudStreamAccumulator(provider: .chatCompletions, responseKind: .textCompletion)
    var snapshots: [String] = []
    let pieces = ["日本語", "👩🏽‍💻", "e\u{301}", "条件は未確定"]
    for piece in pieces {
      try chat.consume(json(["choices": [["delta": ["content": piece]]]]))
      snapshots.append(chat.text)
    }
    try chat.consume(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
    try chat.consume("[DONE]")
    let chatResult = try CloudSummaryResponse(chat.response(), provider: .chatCompletions)
    precondition(chatResult.text == pieces.joined())
    precondition(snapshots[0] == "日本語" && snapshots[1] == "日本語👩🏽‍💻", "Published snapshots mutated")

    var blocks = CloudStreamAccumulator(provider: .anthropic, responseKind: .textCompletion)
    for (index, text) in [(2, "後"), (0, "前")] {
      try blocks.consume(json(["type": "content_block_start", "index": index, "content_block": ["type": "text", "text": text]]))
    }
    try blocks.consume(#"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"半"}}"#)
    try blocks.consume(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"半"}}"#)
    let snapshot = blocks.text
    for index in [0, 2] { try blocks.consume(json(["type": "content_block_stop", "index": index])) }
    try blocks.consume(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
    try blocks.consume(#"{"type":"message_stop"}"#)
    precondition(snapshot == "前半後半" && blocks.text == snapshot)
    let blockResult = try CloudSummaryResponse(blocks.response(), provider: .anthropic)
    precondition(blockResult.text == snapshot)

    var invalid = CloudStreamAccumulator(provider: .chatCompletions, responseKind: .textCompletion)
    do { try invalid.consume(#"{"choices":[{"delta":{"content":123}}]}"#); preconditionFailure("Invalid content accepted") }
    catch AIAnswerFailure.server {}
    var bounded = CloudStreamAccumulator(provider: .chatCompletions, responseKind: .textCompletion)
    let cap = String(repeating: "x", count: CloudStreamAccumulator.maximumRetainedTextBytes)
    try bounded.consume(json(["choices": [["delta": ["content": cap]]]]))
    do { try bounded.consume(#"{"choices":[{"delta":{"content":"x"}}]}"#); preconditionFailure("Retained limit weakened") }
    catch AIAnswerFailure.executionLimit {}
  }

  struct Bytes: AsyncSequence {
    var data: Data
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(data: data) }
    struct AsyncIterator: AsyncIteratorProtocol {
      var data: Data
      var offset = 0
      mutating func next() async throws -> UInt8? {
        try Task.checkCancellation()
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
      }
    }
  }
}
