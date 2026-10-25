import Foundation

@main
enum DeepSeekSummaryChecks {
  @MainActor static func main() async throws {
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
      let response = try await CloudTurnStreamReader.response(from: Bytes(data: bytes), provider: .chatCompletions,
        responseKind: .textCompletion, now: {
          defer { tick += 1 }
          return start.advanced(by: .milliseconds(tick * 6))
        }, onActivity: { activity += 1 }, onText: { publications.append($0) })
      let result = try CloudSummaryResponse(response, provider: .chatCompletions)
      precondition(result.text == "## 要約\n条件を維持する。")
      let message = ((response["choices"] as! [[String: Any]])[0]["message"] as! [String: Any])
      precondition(message["reasoning_content"] == nil, "Summary retained private inference text it never uses")
      precondition(activity > 50 && publications == [result.text], "Real inference activity was hidden or private output was published")
      var bounded = CloudSSEEventDecoder(maximumBytes: 1_024, maximumBufferedBytes: 16)
      for _ in 0..<16 { _ = try bounded.consume(120) }
      do { _ = try bounded.consume(120); preconditionFailure("Oversized SSE event retained") }
      catch AIAnswerFailure.executionLimit {}
      print("DeepSeekSummaryChecks: PASS; bounded summary wire budget, final document intact, no reasoning retained")
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
