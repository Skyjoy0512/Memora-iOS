import Foundation

@main
enum MarkdownStreamingBenchmark {
  static func main() {
    let source = (0..<120).map { "## 議題\($0)\n\n日本語の検証用本文です。担当と期限は記録の根拠を確認します。\n\n- 決定したこと\n- 次回の確認事項\n\n" }.joined()
    let scalars = Array(source.unicodeScalars)
    let updates = stride(from: 80, to: scalars.count, by: 80).map { String(String.UnicodeScalarView(scalars.prefix($0))) } + [source]
    var fullTimes: [Double] = []
    var incrementalTimes: [Double] = []
    var count = 0
    var parsed = 0
    let clock = ContinuousClock()
    for _ in 0..<11 {
      var total = 0
      let fullStart = clock.now
      for update in updates { total += MarkdownBlockParser.sourcedBlocks(for: update).count }
      fullTimes.append(milliseconds(fullStart.duration(to: clock.now)))
      var stream = IncrementalMarkdown()
      let start = clock.now
      for update in updates { stream.update(update, isStreaming: true) }
      stream.update(source, isStreaming: false)
      incrementalTimes.append(milliseconds(start.duration(to: clock.now)))
      precondition(stream.blocks == MarkdownBlockParser.blocks(for: source))
      count = total
      parsed = stream.parsedBytes
    }
    fullTimes.sort(); incrementalTimes.sort()
    print("Synthetic host Swift -O; \(source.utf8.count) bytes; \(updates.count) updates; 11 samples; block checksum \(count)")
    print("Full reparse median/p95 ms: \(fullTimes[5]) / \(fullTimes[10])")
    print("Incremental median/p95 ms: \(incrementalTimes[5]) / \(incrementalTimes[10])")
    print("Parsed input bytes full/incremental: \(updates.reduce(0) { $0 + $1.utf8.count }) / \(parsed)")
    print("This compares parser strategies, not baseline Text UI, network latency, frames or iPhone Release performance.")
  }

  static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
  }
}
