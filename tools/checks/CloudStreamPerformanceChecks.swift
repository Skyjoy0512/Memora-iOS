import Foundation
import Darwin

@main
struct CloudStreamPerformanceChecks {
  static func main() throws {
    let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 21
    precondition((1...101).contains(iterations))
    let piece = "決定は条件付き。予算は150万円、期限は未定です。👩🏽‍💻\n"
    let provider: CloudStreamAccumulator.Provider = CommandLine.arguments[2] == "chat" ? .chatCompletions : .anthropic
    let count = Int(CommandLine.arguments[3])!
    precondition([1_000, 5_000, 10_000].contains(count))
        let payload = provider == .chatCompletions
          ? try json(["choices": [["delta": ["content": piece]]]])
          : try json(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": piece]])
        let expected = String(repeating: piece, count: count)
        var durations: [Double] = []
        for _ in 0..<iterations {
          let start = ContinuousClock.now
          try autoreleasepool {
          var accumulator = CloudStreamAccumulator(provider: provider, responseKind: .textCompletion)
          if provider == .anthropic {
            try accumulator.consume(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
          }
          for _ in 0..<count { try accumulator.consume(payload) }
          if provider == .chatCompletions {
            try accumulator.consume(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
            try accumulator.consume("[DONE]")
          } else {
            try accumulator.consume(#"{"type":"content_block_stop","index":0}"#)
            try accumulator.consume(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
            try accumulator.consume(#"{"type":"message_stop"}"#)
          }
          let result = try CloudSummaryResponse(accumulator.response(), provider: provider)
          precondition(result.text == expected && !result.wasCutOff && accumulator.text == expected)
          }
          let duration = start.duration(to: .now).components
          durations.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
        }
        durations.sort()
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        let row: [String: Any] = ["provider": provider == .chatCompletions ? "chatCompletions" : "anthropic",
          "deltas": count, "outputBytes": expected.utf8.count, "samples": iterations,
          "medianMS": durations[iterations / 2], "p95MS": durations[Int(ceil(Double(iterations) * 0.95)) - 1],
          "maxMS": durations.last!, "processPeakRSSBytes": usage.ru_maxrss]
        print(try json(row))
        fflush(stdout)
  }

  static func json(_ value: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
  }
}
