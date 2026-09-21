import Foundation
import Observation

/// Timings for the paths that matter when comparing builds. An entry holds a
/// name, a duration, how many items were involved, and the build it came from —
/// never a transcript, audio, or a key, so the log can be inspected or shared
/// without exposing what was recorded.
@MainActor
@Observable
final class PerformanceLog {
  struct Entry: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var milliseconds: Double
    /// How many items the work covered, when that is known.
    var count: Int?
    var recordedAt: Date
    var build: String
    var device: String
  }

  struct Stats: Equatable {
    var samples: Int
    var median: Double
    var p95: Double
    var maximum: Double
  }

  private(set) var entries: [Entry] = []
  @ObservationIgnored private let capacity = 500
  @ObservationIgnored private let storeKey = "memoraPerformanceLog"

  /// One log for the app, so a measurement taken in a service lands beside the
  /// ones the model takes and can be compared as a set.
  static let shared = PerformanceLog()

  /// Reads what earlier runs recorded. Called once the store is ready.
  func loadStored() {
    guard let data = RecordStore.read(storeKey),
          let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return }
    entries = stored
  }

  /// Records one timing. `count` is a number, never content.
  func record(_ name: String, milliseconds: Double, count: Int? = nil) {
    entries.append(
      Entry(
        id: UUID(),
        name: name,
        milliseconds: milliseconds,
        count: count,
        recordedAt: .now,
        build: Bundle.main.appVersion,
        device: Self.deviceModel
      )
    )
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
    persist()
  }

  /// Times an async piece of work and records it, returning the result.
  func measure<T>(_ name: String, count: ((T) -> Int?)? = nil, _ work: () async -> T) async -> T {
    let start = Date()
    let result = await work()
    record(name, milliseconds: Date.now.timeIntervalSince(start) * 1_000, count: count?(result))
    return result
  }

  /// Times synchronous work, such as reading the store at launch.
  func measureSync<T>(_ name: String, count: ((T) -> Int?)? = nil, _ work: () -> T) -> T {
    let start = Date()
    let result = work()
    record(name, milliseconds: Date.now.timeIntervalSince(start) * 1_000, count: count?(result))
    return result
  }

  func stats(for name: String) -> Stats? {
    let values = entries.filter { $0.name == name }.map(\.milliseconds).sorted()
    guard !values.isEmpty else { return nil }
    return Stats(
      samples: values.count,
      median: values[values.count / 2],
      p95: values[min(values.count - 1, Int(Double(values.count) * 0.95))],
      maximum: values[values.count - 1]
    )
  }

  var names: [String] {
    Array(Set(entries.map(\.name))).sorted()
  }

  func reset() {
    entries = []
    persist()
  }

  private func persist() {
    RecordStore.save(entries, key: storeKey)
  }

  private static var deviceModel: String {
    var info = utsname()
    uname(&info)
    let machine = withUnsafeBytes(of: &info.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
    return machine.isEmpty ? "unknown" : machine
  }
}
