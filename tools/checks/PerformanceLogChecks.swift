import Foundation
import Synchronization

@main
struct PerformanceLogChecks {
  @MainActor static func main() async throws {
    let log = PerformanceLog()
    for value in 0..<600 { log.record("fixture", milliseconds: Double(value)) }
    precondition(log.entries.count == 500 && log.entries.first?.milliseconds == 100)
    precondition(log.stats(for: "fixture") == PerformanceLog.Stats(samples: 500, median: 350, p95: 575, maximum: 599))
    log.flush()
    await RecordStore.flushAsync()
    guard case .data(let saved) = RecordStore.load("memoraPerformanceLog") else { preconditionFailure() }
    let restored = try JSONDecoder().decode([PerformanceLog.Entry].self, from: saved)
    precondition(restored == log.entries)
    var samples: [Double] = []
    LocalStore.shared.resetWrites()
    for _ in 0..<21 {
      let start = ContinuousClock.now
      for value in 0..<100 { log.record("fixture", milliseconds: Double(value)) }
      log.flush()
      await RecordStore.flushAsync()
      let duration = start.duration(to: .now).components
      samples.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "log-burst-100,median=%.3f,p95=%.3f,max=%.3f,writes=%d", samples[10], samples[19], samples[20], LocalStore.shared.writeCount))
#if !BASELINE
    LocalStore.shared.failNextWrite()
    log.record("retry", milliseconds: 1)
    log.flushNow()
    // A failed flush retains the prior bytes, and the in-memory revision retries.
    log.flushNow()
    guard case .data(let retryData) = RecordStore.load("memoraPerformanceLog") else { preconditionFailure() }
    let retried = try JSONDecoder().decode([PerformanceLog.Entry].self, from: retryData)
    precondition(retried.last?.name == "retry")
#endif
    log.reset()
    await RecordStore.flushAsync()
    guard case .data(let resetData) = RecordStore.load("memoraPerformanceLog") else { preconditionFailure() }
    let empty = try JSONDecoder().decode([PerformanceLog.Entry].self, from: resetData)
    precondition(empty.isEmpty && log.entries.isEmpty)
    print("PerformanceLogChecks: passed (capacity, stats, ordered reset, retry, snapshot round trip)")
  }
}

// No app files or defaults are changed by these checks.
final class LocalStore: Sendable {
  static let shared = LocalStore()
  enum StoreError: Error { case statement(Int32) }
  enum ReadOutcome { case missing, data(Data), failed }
  private struct State { var documents: [String: Data] = [:]; var writes = 0; var fails = false }
  private let state = Mutex(State())
  var writeCount: Int { state.withLock { $0.writes } }
  func resetWrites() { state.withLock { $0.writes = 0 } }
  func failNextWrite() { state.withLock { $0.fails = true } }
  func prepare() throws {}
  func readOutcome(_ key: String) -> ReadOutcome { state.withLock { $0.documents[key].map(ReadOutcome.data) ?? .missing } }
  func write(_ key: String, data: Data) throws { try applyBatch(writes: [(key, data)], removing: []) }
  func remove(_ key: String) throws { try applyBatch(writes: [], removing: [key]) }
  func applyBatch(writes: [(key: String, data: Data)], removing: [String]) throws {
    try state.withLock { value in
      if value.fails { value.fails = false; throw StoreError.statement(1) }
      value.writes += 1
      for (key, data) in writes { value.documents[key] = data }
      for key in removing { value.documents.removeValue(forKey: key) }
    }
  }
}

extension Bundle { var appVersion: String { "fixture" } }
