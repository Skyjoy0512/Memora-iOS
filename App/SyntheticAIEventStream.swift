#if DEBUG
import Foundation

/// Offline bytes exercise the same SSE receive loop as BYOK, without keys or HTTP.
struct SyntheticAIEventStream: AsyncSequence {
  private var frames: [Data]
  private var interval: Duration

  init(text: String, interval: Duration = .milliseconds(100)) throws {
    self.interval = interval
    let scalars = Array(text.unicodeScalars)
    frames = try stride(from: 0, to: scalars.count, by: 12).map { start in
      let value = String(String.UnicodeScalarView(scalars[start..<Swift.min(start + 12, scalars.count)]))
      return try Self.frame(["choices": [["index": 0, "delta": ["content": value]]]])
    }
    frames.append(try Self.frame(["choices": [["index": 0, "delta": [String: Any](), "finish_reason": "stop"]]]))
    frames.append(Data("data: [DONE]\r\n\r\n".utf8))
  }

  func makeAsyncIterator() -> AsyncIterator { AsyncIterator(frames: frames, interval: interval) }

  private static func frame(_ object: [String: Any]) throws -> Data {
    var result = Data("data: ".utf8)
    result.append(try JSONSerialization.data(withJSONObject: object))
    result.append(Data("\r\n\r\n".utf8))
    return result
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    var frames: [Data]
    var interval: Duration
    private var frame = 0
    private var offset = 0

    init(frames: [Data], interval: Duration) {
      self.frames = frames
      self.interval = interval
    }

    mutating func next() async throws -> UInt8? {
      try Task.checkCancellation()
      guard frame < frames.count else { return nil }
      if offset == 0, frame > 0 { try await Task.sleep(for: interval) }
      let value = frames[frame][offset]
      offset += 1
      if offset == frames[frame].count { frame += 1; offset = 0 }
      return value
    }
  }
}
#endif
