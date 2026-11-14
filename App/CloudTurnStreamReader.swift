import Foundation

/// The production receive loop also accepts synthetic byte sequences, so event
/// framing, publication timing and cancellation can be tested without an API.
enum CloudTurnStreamReader {
  @concurrent
  static func jsonResponse<Bytes: AsyncSequence & Sendable>(from bytes: Bytes) async throws -> [String: Any]
    where Bytes.Element == UInt8 {
    var data = Data()
    defer { SummaryDiagnostics.current?.record(.wireBytes, code: data.count) }
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < AgentSessionBudget.maximumResponseBytes else { throw AIAnswerFailure.executionLimit }
      data.append(byte)
    }
    try Task.checkCancellation()
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw AIAnswerFailure.server }
    return object
  }

  @concurrent
  static func response<Bytes: AsyncSequence & Sendable>(
    from bytes: Bytes,
    provider: CloudStreamAccumulator.Provider,
    responseKind: CloudStreamAccumulator.ResponseKind = .agentTurn,
    now: @Sendable () -> ContinuousClock.Instant = { .now },
    onActivity: (@MainActor () -> Void)? = nil,
    onText: @MainActor (String) -> Void
  ) async throws -> [String: Any] where Bytes.Element == UInt8 {
    try Task.checkCancellation()
    var accumulator = CloudStreamAccumulator(provider: provider, responseKind: responseKind)
    var events = CloudSSEEventDecoder()
    if responseKind == .textCompletion { events.maximumBytes = CloudStreamAccumulator.maximumSummaryWireBytes }
    defer {
      SummaryDiagnostics.current?.record(.wireBytes, code: events.receivedBytes)
      SummaryDiagnostics.current?.providerStopped(accumulator.finishReason)
    }
    var lastPublication = now()
    var published = ""
    var receivedOutputEvents = 0
    var receivedTextEvents = 0
    var receivedReasoningEvents = 0
    var lastActivity: ContinuousClock.Instant?
    for try await byte in bytes {
      try Task.checkCancellation()
      if let payload = try events.consume(byte) {
        try accumulator.consume(payload)
        let instant = now()
        if accumulator.reasoningEvents > 0, receivedReasoningEvents == 0 {
          SummaryDiagnostics.current?.record(.firstReasoning)
        }
        if accumulator.textEvents > receivedTextEvents { SummaryDiagnostics.current?.outputReceived() }
        receivedTextEvents = accumulator.textEvents
        receivedReasoningEvents = accumulator.reasoningEvents
        if accumulator.outputEvents > receivedOutputEvents {
          if lastActivity == nil || lastActivity!.duration(to: instant) >= .seconds(1) {
            await onActivity?()
            lastActivity = instant
          }
        }
        receivedOutputEvents = accumulator.outputEvents
        if accumulator.text != published, published.isEmpty || lastPublication.duration(to: instant) >= .milliseconds(100) || accumulator.isFinished {
          published = accumulator.text
          lastPublication = instant
          await onText(published)
        }
        if accumulator.isFinished { break }
      }
    }
    if !accumulator.isFinished, let payload = try events.finish() { try accumulator.consume(payload) }
    try Task.checkCancellation()
    let result = try accumulator.response()
    SummaryDiagnostics.current?.receivedUsage(result, usesAnthropicAPI: provider == .anthropic)
    SummaryDiagnostics.current?.responseCompleted()
    if accumulator.text != published { await onText(accumulator.text) }
    return result
  }
}
