import CryptoKit
import Foundation
import OSLog
import Synchronization

/// An allow-listed timeline: no prompts, responses, URLs, keys or error descriptions.
final class SummaryDiagnostics: Sendable {
  enum Stage: String, Sendable {
    case started, analysis, generation, request, httpResponse, firstToken, lastToken
    case responseComplete, parseStarted, parseCompleted, saveStarted, saveCompleted
    case backgroundExpiration, cancelled, contextChanged, saveFailed, failed, completed
    case onDeviceSection, onDeviceError, wireBytes
  }
  struct Event: Sendable {
    var stage: Stage
    var elapsed: Double
    var code: Int?
    var failure: String? = nil
  }
  private struct State: Sendable {
    var events: [Event] = []
    var firstOutput = false
    var lastOutput: Event?
  }
  @TaskLocal static var current: SummaryDiagnostics?
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
      if value.events.count < 256 { value.events.append(event) }
    }
    Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) elapsed=\(event.elapsed, privacy: .public) code=\(code ?? 0, privacy: .public)")
  }

  func outputReceived() {
    let first = state.withLock { value in
      let first = !value.firstOutput
      value.firstOutput = true
      value.lastOutput = event(.lastToken)
      return first
    }
    if first { record(.firstToken) }
  }

  func responseCompleted() {
    let last = state.withLock { value -> Event? in
      let last = value.lastOutput
      value.lastOutput = nil
      value.firstOutput = false
      if let last, value.events.count < 256 { value.events.append(last) }
      return last
    }
    if let last {
      Self.logger.info("job=\(self.jobID.uuidString, privacy: .public) stage=lastToken elapsed=\(last.elapsed, privacy: .public)")
    }
    record(.responseComplete)
  }

  func failed(_ failure: AIAnswerFailure) {
    var entry = event(.failed)
    entry.failure = String(describing: failure)
    state.withLock { if $0.events.count < 256 { $0.events.append(entry) } }
    Self.logger.error("job=\(self.jobID.uuidString, privacy: .public) failure=\(entry.failure ?? "unknown", privacy: .public) elapsed=\(entry.elapsed, privacy: .public)")
  }

  var events: [Event] { state.withLock { $0.events + ($0.lastOutput.map { [$0] } ?? []) } }
  var report: String {
    (["job=\(jobID.uuidString) started=\(startedAt.ISO8601Format())", metadata] + events.map {
      String(format: "%.3fs %@ code=%d", $0.elapsed, $0.stage.rawValue, $0.code ?? 0) + ($0.failure.map { " failure=\($0)" } ?? "")
    }).joined(separator: "\n")
  }
  static var reports: [String] { recent.withLock { $0 }.reversed().map(\.report) }

  private func event(_ stage: Stage, code: Int? = nil) -> Event {
    let duration = start.duration(to: .now).components
    return Event(stage: stage, elapsed: Double(duration.seconds) + Double(duration.attoseconds) / 1e18, code: code)
  }
}
