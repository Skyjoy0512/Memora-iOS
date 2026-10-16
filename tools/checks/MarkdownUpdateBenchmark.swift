import Foundation

@main
enum MarkdownUpdateBenchmark {
  static func main() throws {
    let fixtures: [(String, String)] = [
      ("sections", (0..<120).map { "## 議題\($0)\n\n日本語の検証用本文です。担当と期限は記録の根拠を確認します。\n\n- 決定したこと\n- 次回の確認事項\n\n" }.joined()),
      ("dense-list", (0..<500).map { "- 項目\($0)：担当と期限を確認します。【資料1】\n" }.joined()),
      ("code", "```swift\n" + (0..<500).map { "let value\($0) = \"日本語の検証用文字列\"\n" }.joined() + "```\n"),
      ("table", "| 項目 | 状態 |\n| --- | --- |\n" + (0..<300).map { "| 項目\($0) | 記録の根拠を確認 |\n" }.joined()),
      ("paragraph", String(repeating: "日本語の長い未確定段落です。", count: 700))
    ]
    var reports: [[String: Any]] = []
    for (name, text) in fixtures {
      let scalars = Array(text.unicodeScalars)
      let updates = stride(from: 80, to: scalars.count, by: 80).map {
        String(String.UnicodeScalarView(scalars.prefix($0)))
      } + [text]
      let expected = BaselineMarkdownBlockParser.sourcedBlocks(for: text)
      precondition(expected == MarkdownBlockParser.sourcedBlocks(for: text))
      var baseline: [Sample] = [], current: [Sample] = []
      for iteration in 0..<23 {
        // Alternate order to avoid consistently favouring the warmer variant.
        let before: Sample, after: Sample
        if iteration.isMultiple(of: 2) {
          before = measureBaseline(updates, expected: expected.map(\.block))
          after = measureCurrent(updates, expected: expected.map(\.block))
        } else {
          after = measureCurrent(updates, expected: expected.map(\.block))
          before = measureBaseline(updates, expected: expected.map(\.block))
        }
        if iteration >= 2 { baseline.append(before); current.append(after) }
      }
      reports.append(["fixture": name, "bytes": text.utf8.count, "updates": updates.count,
        "baseline": stats(baseline), "current": stats(current),
        "final_blocks": expected.count])
    }
    let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  private struct Sample {
    var total: Double
    var updateMaximum: Double
    var first: Double
    var completion: Double
    var parsedBytes: Int
  }

  private static func measureBaseline(_ updates: [String], expected: [MarkdownBlock]) -> Sample {
    var stream = BaselineIncrementalMarkdown()
    var total = 0.0, maximum = 0.0, first = 0.0
    for (index, text) in updates.enumerated() {
      let start = ContinuousClock.now
      stream.update(text, isStreaming: true)
      let blocks = stream.blocks
      let elapsed = milliseconds(start.duration(to: .now))
      total += elapsed; maximum = max(maximum, elapsed)
      if index == 0 { first = elapsed }
      precondition(!blocks.isEmpty)
    }
    let start = ContinuousClock.now
    stream.update(updates.last!, isStreaming: false)
    let complete = stream.blocks
    let completion = milliseconds(start.duration(to: .now))
    precondition(complete == expected)
    return Sample(total: total + completion, updateMaximum: maximum, first: first,
      completion: completion, parsedBytes: stream.parsedBytes)
  }

  private static func measureCurrent(_ updates: [String], expected: [MarkdownBlock]) -> Sample {
    var stream = IncrementalMarkdown()
    var total = 0.0, maximum = 0.0, first = 0.0
    for (index, text) in updates.enumerated() {
      let start = ContinuousClock.now
      stream.update(text, isStreaming: true)
      let blocks = stream.blocks
      let elapsed = milliseconds(start.duration(to: .now))
      total += elapsed; maximum = max(maximum, elapsed)
      if index == 0 { first = elapsed }
      precondition(!blocks.isEmpty)
    }
    let start = ContinuousClock.now
    stream.update(updates.last!, isStreaming: false)
    let complete = stream.blocks
    let completion = milliseconds(start.duration(to: .now))
    precondition(complete == expected)
    return Sample(total: total + completion, updateMaximum: maximum, first: first,
      completion: completion, parsedBytes: stream.parsedBytes)
  }

  private static func stats(_ samples: [Sample]) -> [String: Any] {
    func distribution(_ values: [Double]) -> [String: Double] {
      let sorted = values.sorted()
      return ["median_ms": sorted[10], "p95_ms": sorted[19], "maximum_ms": sorted[20]]
    }
    return ["total": distribution(samples.map(\.total)),
      "largest_update": distribution(samples.map(\.updateMaximum)),
      "first": distribution(samples.map(\.first)), "completion": distribution(samples.map(\.completion)),
      "parsed_bytes": samples[0].parsedBytes]
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }
}
