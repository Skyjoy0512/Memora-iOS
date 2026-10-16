import Foundation

/// The production receive loop also accepts synthetic byte sequences, so event
/// framing, publication timing and cancellation can be tested without an API.
enum CloudTurnStreamReader {
  @MainActor
  static func response<Bytes: AsyncSequence>(
    from bytes: Bytes,
    provider: CloudStreamAccumulator.Provider,
    now: () -> ContinuousClock.Instant = { .now },
    onText: @MainActor (String) -> Void
  ) async throws -> [String: Any] where Bytes.Element == UInt8 {
    try Task.checkCancellation()
    var accumulator = CloudStreamAccumulator(provider: provider)
    var events = CloudSSEEventDecoder()
    var lastPublication = now()
    var published = ""
    for try await byte in bytes {
      try Task.checkCancellation()
      if let payload = try events.consume(byte) {
        try accumulator.consume(payload)
        let instant = now()
        if accumulator.text != published, published.isEmpty || lastPublication.duration(to: instant) >= .milliseconds(100) || accumulator.isFinished {
          published = accumulator.text
          lastPublication = instant
          onText(published)
        }
        if accumulator.isFinished { break }
      }
    }
    if !accumulator.isFinished, let payload = try events.finish() { try accumulator.consume(payload) }
    try Task.checkCancellation()
    let result = try accumulator.response()
    if accumulator.text != published { onText(accumulator.text) }
    return result
  }
}
