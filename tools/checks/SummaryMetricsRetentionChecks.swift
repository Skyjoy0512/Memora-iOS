import Foundation

@main enum SummaryMetricsRetentionChecks {
  static func main() {
    let diagnostic = SummaryDiagnostics(jobID: UUID(), engine: "fixture", provider: "fixture", model: "fixture", characters: 0, segments: 0)
    diagnostic.record(.sourceOriginalBytes, code: 200)
    diagnostic.record(.sourceWireBytes, code: 150)
    for _ in 0..<3 { diagnostic.record(.artifactCacheHit) }
    for number in 0..<300 {
      SummaryDiagnostics.$requestID.withValue(UUID()) {
        diagnostic.record(.request)
        diagnostic.record(.httpResponse, code: number % 10 == 0 ? 429 : 200)
        if number % 10 == 0 { diagnostic.responseFailed(cancelled: false) }
        else {
          diagnostic.record(.firstReasoning)
          diagnostic.outputReceived()
          diagnostic.receivedUsage(["usage": ["prompt_tokens": 100, "completion_tokens": 20]], usesAnthropicAPI: false)
          diagnostic.responseCompleted()
        }
      }
    }
    let metrics = diagnostic.metrics
    precondition(metrics.timelineIncomplete && !metrics.measurementsIncomplete)
    precondition(metrics.requestCount == 300 && metrics.requests.count == 300 && diagnostic.events.count == 256)
    precondition(metrics.requests.filter { $0.outcome == .failed }.count == 30)
    precondition(metrics.requests.filter { $0.inputTokens == nil }.count == 30)
    precondition(metrics.requests.compactMap(\.inputTokens).reduce(0, +) == 27_000)
    precondition(metrics.sourceOriginalBytes == 200 && metrics.sourceWireBytes == 150 && metrics.artifactCacheHits == 3)
    precondition(metrics.parseSeconds == nil && metrics.saveSeconds == nil)
    precondition(metrics.requests.allSatisfy { $0.totalSeconds != nil && $0.reasoningTokens == nil })
    let bounded = SummaryDiagnostics(jobID: UUID(), engine: "fixture", provider: "fixture", model: "fixture", characters: 0, segments: 0)
    for _ in 0..<4097 {
      SummaryDiagnostics.$requestID.withValue(UUID()) { bounded.record(.request); bounded.responseFailed(cancelled: true) }
    }
    precondition(bounded.metrics.requestCount == 4097 && bounded.metrics.requests.count == 4096 && bounded.metrics.measurementsIncomplete)
    precondition(bounded.metricsJSON != nil)
    print("SummaryMetricsRetentionChecks: PASS; 300 request counters survive display eviction, failures and unknown usage remain distinct; 4096 tracker bound reports missing measurements instead of a complete total. No API.")
  }
}
