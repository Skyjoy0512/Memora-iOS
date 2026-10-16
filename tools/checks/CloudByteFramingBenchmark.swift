import Foundation

/// Synthetic host benchmark; this excludes URLSession, SwiftUI and device performance.
@main
struct CloudByteFramingBenchmark {
  static func main() async throws {
    let event = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"日本語断片\"}}]}\r\n\r\n"
    let wire = Data(String(repeating: event, count: 1_024).utf8)
    var samples: [Double] = []
    for run in 0..<12 {
      let start = ContinuousClock.now
      let frames = try await read(wire)
      precondition(frames == 1_024)
      let elapsed = start.duration(to: .now).components
      let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
      if run > 0 { samples.append(milliseconds) }
    }
    print("Cloud byte framing: synthetic host -O, \(wire.count) bytes, 1024 SSE events, 11 runs after warmup")
    print(String(format: "Bounded SSE framing p50=%.2fms p95=%.2fms", samples.sorted()[5], samples.sorted()[10]))
  }

  static func read(_ data: Data) async throws -> Int {
    var frames = 0
    var events = CloudSSEEventDecoder()
    for await byte in Bytes(data: data) {
      if try events.consume(byte) != nil { frames += 1 }
    }
    return frames
  }

  struct Bytes: AsyncSequence {
    var data: Data
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(data: data) }
    struct AsyncIterator: AsyncIteratorProtocol {
      var data: Data
      var offset = 0
      mutating func next() async -> UInt8? {
        guard offset < data.count else { return nil }
        defer { offset += 1 }
        return data[offset]
      }
    }
  }
}
