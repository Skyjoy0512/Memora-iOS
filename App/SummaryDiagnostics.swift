import CryptoKit
import CoreFoundation
import Foundation
import OSLog
import Synchronization

/// An allow-listed timeline: no prompts, responses, URLs, keys or error descriptions.
final class SummaryDiagnostics: Sendable {
  enum Stage: String, Sendable {
    case started, analysis, generation, request, httpResponse, firstReasoning, firstToken, lastToken
    case responseComplete, parseStarted, parseCompleted, saveStarted, saveCompleted
    case backgroundExpiration, cancelled, contextChanged, saveFailed, failed, completed
    case onDeviceSection, onDeviceError, wireBytes
    case inputTokens, outputTokens, reasoningTokens, cachedInputTokens, cacheWriteTokens
    case sourceWireBytes, sourceOriginalBytes
    case enteredForeground, enteredBackground
    case providerStop
    case processingMode
    case backgroundWaiting, backgroundGranted, backgroundFallback
    case backgroundRequested, backgroundAccepted, backgroundRejected
  }
  struct Event: Sendable {
    var stage: Stage
    var elapsed: Double
    var code: Int?
    var failure: String? = nil
    var requestID: UUID? = nil
    var reason: String? = nil
  }
  private struct Output: Sendable {
    var firstReceived = false
    var last: Event?
  }
  private struct State: Sendable {
    var events: [Event] = []
    var omittedEvents = 0
    var outputs: [UUID?: Output] = [:]

    mutating func append(_ event: Event) {
      // Keep the job origin and recent timeline, especially the final save or
      // failure. A long, sectioned job must not hide its eventual outcome.
      if events.count == 256 { events.remove(at: 1); omittedEvents += 1 }
      events.append(event)
    }
  }
  @TaskLocal static var current: SummaryDiagnostics?
  @TaskLocal static var requestID: UUID?
  private static let logger = Logger(subsystem: "app.memora", category: "SummaryTimeline")
  private static let recent = Mutex<[SummaryDiagnostics]>([])
  let jobID: UUID
  let startedAt: Date
  let metadata: String
  private let start = ContinuousClock.now
  private let state = Mutex(State())

  init(jobID: UUID, engine: String, provider: String, model: String, characters: Int, segments: Int) {
    self.jobID = jobID
    startedAt = .now
    // Registered model IDs can be arbitrary user input. A fingerprint identifies
    // the same model across runs without exposing a custom name or endpoint.
    let modelID = SHA256.hash(data: Data(model.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    metadata = "engine=\(engine) provider=\(provider) modelSHA256=\(modelID) characters=\(characters) segments=\(segments)"
    Self.recent.withLock { runs in
      runs.append(self)
      if runs.count > 12 { runs.removeFirst(runs.count - 12) }
    }
    record(.started)
    Self.logger.info("job=\(jobID.uuidString, privacy: .public) \(self.metadata, privacy: .public)")
  }

  func record(_ stage: Stage, code: Int? = nil) {
    let event = event(stage, code: code)
    state.withLock { value in
      value.append(event)
    }
    Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) request=\(event.requestID?.uuidString ?? "job", privacy: .public) stage=\(stage.rawValue, privacy: .public) elapsed=\(event.elapsed, privacy: .public) code=\(code ?? 0, privacy: .public)")
  }

  func outputReceived() {
    let first = state.withLock { value -> Event? in
      let first = !value.outputs[Self.requestID, default: Output()].firstReceived
      value.outputs[Self.requestID, default: Output()].firstReceived = true
      var received = event(.lastToken)
      value.outputs[Self.requestID, default: Output()].last = received
      guard first else { return nil }
      // A one-chunk answer has the same first/last instant. Recording the
      // first event afterwards would manufacture a negative generation span.
      received.stage = .firstToken
      value.append(received)
      return received
    }
    if let first {
      Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) request=\(first.requestID?.uuidString ?? "job", privacy: .public) stage=firstToken elapsed=\(first.elapsed, privacy: .public)")
    }
  }

  func responseCompleted() {
    let last = state.withLock { value -> Event? in
      let last = value.outputs.removeValue(forKey: Self.requestID)?.last
      if let last { value.append(last) }
      return last
    }
    if let last {
      Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) request=\(last.requestID?.uuidString ?? "job", privacy: .public) stage=lastToken elapsed=\(last.elapsed, privacy: .public)")
    }
    record(.responseComplete)
  }

  func receivedUsage(_ response: [String: Any], usesAnthropicAPI: Bool) {
    guard let usage = response["usage"] as? [String: Any] else { return }
    let input = usage[usesAnthropicAPI ? "input_tokens" : "prompt_tokens"]
    let output = usage[usesAnthropicAPI ? "output_tokens" : "completion_tokens"]
    let reasoning = (usage["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"]
    let cached = usesAnthropicAPI ? usage["cache_read_input_tokens"] :
      ((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] ?? usage["prompt_cache_hit_tokens"])
    let written = usesAnthropicAPI ? usage["cache_creation_input_tokens"] : nil
    for (stage, raw) in [(Stage.inputTokens, input), (.outputTokens, output), (.reasoningTokens, reasoning),
                         (.cachedInputTokens, cached), (.cacheWriteTokens, written)] {
      guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            let value = Int(exactly: number.doubleValue), value >= 0 else { continue }
      record(stage, code: value)
    }
  }

  func providerStopped(_ raw: String?) {
    guard let raw else { return }
    let known = ["stop", "length", "end_turn", "max_tokens", "tool_calls", "tool_use", "stop_sequence",
      "refusal", "content_filter", "aborted", "insufficient_system_resource", "pause_turn", "model_context_window_exceeded"]
    var entry = event(.providerStop)
    // Unknown provider strings are untrusted and could contain personal data.
    entry.reason = known.contains(raw) ? raw : "unrecognized"
    state.withLock { $0.append(entry) }
    Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) request=\(entry.requestID?.uuidString ?? "job", privacy: .public) stage=providerStop reason=\(entry.reason ?? "unrecognized", privacy: .public) elapsed=\(entry.elapsed, privacy: .public)")
  }

  static func recordLifecycle(jobIDs: Set<UUID>, isForeground: Bool) {
    for run in recent.withLock({ $0 }).filter({ jobIDs.contains($0.jobID) }) {
      run.record(isForeground ? .enteredForeground : .enteredBackground)
    }
  }

  static func recordBackground(jobID: UUID, stage: Stage, code: Int? = nil) {
    recent.withLock { $0.first { $0.jobID == jobID } }?.record(stage, code: code)
  }

  func failed(_ failure: AIAnswerFailure) {
    var entry = event(.failed)
    entry.failure = String(describing: failure)
    state.withLock { $0.append(entry) }
    Self.logger.error("job=\(self.jobID.uuidString, privacy: .public) failure=\(entry.failure ?? "unknown", privacy: .public) elapsed=\(entry.elapsed, privacy: .public)")
  }

  var events: [Event] { state.withLock { $0.events + $0.outputs.values.compactMap(\.last) } }
  var report: String {
    let snapshot = state.withLock { ($0.events + $0.outputs.values.compactMap(\.last), $0.omittedEvents) }
    return (["job=\(jobID.uuidString) started=\(startedAt.ISO8601Format())", metadata,
      "retainedEvents=\(snapshot.0.count) omittedEvents=\(snapshot.1)"] + snapshot.0.map {
      String(format: "%.3fs %@ code=%d", $0.elapsed, $0.stage.rawValue, $0.code ?? 0)
        + ($0.requestID.map { " request=\($0.uuidString)" } ?? "") + ($0.failure.map { " failure=\($0)" } ?? "")
        + ($0.reason.map { " reason=\($0)" } ?? "")
    }).joined(separator: "\n")
  }
  static var reports: [String] { recent.withLock { $0 }.reversed().map(\.report) }

  /// Numeric measurements only. Missing provider counters stay nil rather than
  /// becoming a zero-cost or zero-reasoning claim. Delays include provider work.
  struct Metrics: Codable, Sendable {
    struct Request: Codable, Sendable {
      var id: UUID
      var httpStatus: Int?
      var headerDelaySeconds: Double?
      var firstReasoningDelaySeconds: Double?
      var ttftSeconds: Double?
      var reasoningToBodySeconds: Double?
      var bodyGenerationSeconds: Double?
      var totalSeconds: Double?
      var inputTokens: Int?
      var outputTokens: Int?
      var reasoningTokens: Int?
      var cachedInputTokens: Int?
      var cacheWriteTokens: Int?
    }
    var timelineIncomplete: Bool
    var requests: [Request]
    var parseSeconds: Double?
    var saveSeconds: Double?
    var sourceOriginalBytes: Int?
    var sourceWireBytes: Int?
  }

  var metrics: Metrics {
    let snapshot = state.withLock { ($0.events + $0.outputs.values.compactMap(\.last), $0.omittedEvents) }
    let entries = snapshot.0
    func duration(_ first: Double?, _ last: Double?) -> Double? {
      guard let first, let last, last >= first else { return nil }
      return last - first
    }
    let starts = entries.filter { $0.stage == .request && $0.requestID != nil }
    let requests = starts.map { start -> Metrics.Request in
      let values = entries.filter { $0.requestID == start.requestID }
      func time(_ stage: Stage) -> Double? { values.first { $0.stage == stage }?.elapsed }
      func count(_ stage: Stage) -> Int? { values.last { $0.stage == stage }?.code }
      return Metrics.Request(id: start.requestID!, httpStatus: count(.httpResponse),
        headerDelaySeconds: duration(start.elapsed, time(.httpResponse)),
        firstReasoningDelaySeconds: duration(start.elapsed, time(.firstReasoning)),
        ttftSeconds: duration(start.elapsed, time(.firstToken)),
        reasoningToBodySeconds: duration(time(.firstReasoning), time(.firstToken)),
        bodyGenerationSeconds: duration(time(.firstToken), time(.lastToken)),
        totalSeconds: duration(start.elapsed, time(.responseComplete)),
        inputTokens: count(.inputTokens), outputTokens: count(.outputTokens), reasoningTokens: count(.reasoningTokens),
        cachedInputTokens: count(.cachedInputTokens), cacheWriteTokens: count(.cacheWriteTokens))
    }
    func span(_ begin: Stage, _ end: Stage) -> Double? {
      duration(entries.first { $0.stage == begin }?.elapsed, entries.last { $0.stage == end }?.elapsed)
    }
    return Metrics(timelineIncomplete: snapshot.1 > 0, requests: requests,
      parseSeconds: span(.parseStarted, .parseCompleted), saveSeconds: span(.saveStarted, .saveCompleted),
      sourceOriginalBytes: entries.last { $0.stage == .sourceOriginalBytes }?.code,
      sourceWireBytes: entries.last { $0.stage == .sourceWireBytes }?.code)
  }

  var metricsJSON: String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(metrics)).flatMap { String(data: $0, encoding: .utf8) }
  }

  private func event(_ stage: Stage, code: Int? = nil) -> Event {
    let duration = start.duration(to: .now).components
    return Event(stage: stage, elapsed: Double(duration.seconds) + Double(duration.attoseconds) / 1e18, code: code, requestID: Self.requestID)
  }
}
