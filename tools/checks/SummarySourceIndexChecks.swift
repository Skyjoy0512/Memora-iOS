import Foundation

@main enum SummarySourceIndexChecks {
  static func main() {
    let segments: [TranscriptSegment] = (0..<1_000).map { index -> TranscriptSegment in
      let certain = index % 2 == 0
      let time = Double(index) * 3
      return TranscriptSegment(id: UUID(), speaker: certain ? "田中 太郎" : "Speaker 2",
      speakerIsCertain: certain, timestamp: time,
      text: "  11月20日ではなく11月27日。API_KEY_Aとapi_key_a、-30万円。条件付きで実行する。\n否定・訂正を保つ。  ",
      endTime: time + 2, speakerID: certain ? "person-1" : nil) }
    let first = SummarySourceIndex(segments), second = SummarySourceIndex(segments)
    precondition(first.lines(hasTimestamps: true) == second.lines(hasTimestamps: true))
    precondition(first.legend == second.legend)
    let lines = first.lines(hasTimestamps: true)
    for (index, entry) in first.entries.enumerated() {
      precondition(entry.segment == segments[index])
      precondition(entry.shortID == "S\(index + 1)")
      precondition(first.originalID(for: entry.shortID) == segments[index].id)
      precondition(first.originalID(for: segments[index].id.uuidString) == segments[index].id)
      precondition(first.validates(id: entry.shortID, quote: "API_KEY_Aとapi_key_a、-30万円"))
      precondition(!first.validates(id: entry.shortID, quote: "捏造された引用は受け付けない"))
      precondition(lines[index].hasSuffix(segments[index].text))
    }
    precondition(first.originalID(for: "S1", allowShortIDs: false) == nil)
    precondition(!first.validates(id: "S1", quote: "API_KEY_Aとapi_key_a、-30万円", allowShortIDs: false))
    precondition(first.originalID(for: "S0") == nil && first.originalID(for: "S1001") == nil)
    precondition(first.originalID(for: UUID().uuidString) == nil)
    let ambiguous = SummarySourceIndex([segments[0], segments[0]])
    precondition(ambiguous.originalID(for: "S1") == nil && ambiguous.originalID(for: "S2") == nil)
    precondition(first.lines(hasTimestamps: false).allSatisfy { $0.hasPrefix("[時刻不明]") })
    let oldBytes = segments.map(MeetingSummaryInput.cloudLine).joined(separator: "\n").utf8.count
    let newBytes = (first.legend + "\n" + first.lines(hasTimestamps: true).joined(separator: "\n")).utf8.count
    precondition(newBytes < oldBytes)
    print("Lossless source IDs: segments=1000 originalBytes=\(oldBytes) compactBytes=\(newBytes); bytes, not model tokens")
    let diagnostics = SummaryDiagnostics(jobID: UUID(), engine: "fixture", provider: "fixture", model: "fixture", characters: 0, segments: 0)
    diagnostics.receivedUsage(["usage": ["prompt_tokens": 100, "completion_tokens": 20, "prompt_tokens_details": ["cached_tokens": 80], "completion_tokens_details": ["reasoning_tokens": 5]]], usesAnthropicAPI: false)
    diagnostics.receivedUsage(["usage": ["input_tokens": 40, "output_tokens": 10, "cache_read_input_tokens": 90, "cache_creation_input_tokens": 60]], usesAnthropicAPI: true)
    diagnostics.receivedUsage(["usage": ["prompt_cache_hit_tokens": true]], usesAnthropicAPI: false)
    precondition(diagnostics.events.filter { $0.stage == .cachedInputTokens }.map(\.code) == [80, 90])
    precondition(diagnostics.events.filter { $0.stage == .cacheWriteTokens }.map(\.code) == [60])
    let request = UUID()
    SummaryDiagnostics.$requestID.withValue(request) {
      diagnostics.record(.request)
      diagnostics.record(.httpResponse, code: 200)
      diagnostics.record(.firstReasoning)
      diagnostics.outputReceived()
      diagnostics.receivedUsage(["usage": ["prompt_tokens": 40, "completion_tokens": 20]], usesAnthropicAPI: false)
      diagnostics.responseCompleted()
    }
    let measured = diagnostics.metrics.requests.first!
    precondition(measured.id == request && measured.httpStatus == 200 && measured.inputTokens == 40)
    precondition(measured.reasoningTokens == nil && measured.cachedInputTokens == nil)
    precondition(measured.ttftSeconds != nil && measured.reasoningToBodySeconds != nil && measured.bodyGenerationSeconds != nil)
    precondition(diagnostics.metrics.saveSeconds == nil && diagnostics.metricsJSON != nil)
    print("SummarySourceIndexChecks: PASS; snapshot round trips, exact raw text, speakers, duplicate IDs, unknown references, cache usage and unknown counters")
  }
}
