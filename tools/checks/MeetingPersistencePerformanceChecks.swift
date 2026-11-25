import Foundation
import Darwin
import SQLite3

/// Measures whole-document storage using synthetic meetings and production SQLite.
@main
enum MeetingPersistencePerformanceChecks {
  static func main() throws {
    let count = Int(CommandLine.arguments[1])!
    let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let segmentCount = Int(CommandLine.arguments[3])!
    let sampleCount = Int(CommandLine.arguments[4])!
    let url = folder.appendingPathComponent("meetings-\(count).sqlite")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    let transcript = (0..<segmentCount).map { index in TranscriptSegment(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!, speaker: "話者1", speakerIsCertain: false,
      timestamp: Double(index * 15), text: "予算は150万円。承認がなければ公開しない。期限は未定です。") }
    let meetings = (0..<count).map { index in Meeting(id: UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", index + 1))!, title: "合成記録\(index)", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      duration: 300, source: .importFile, status: .ready, summary: String(repeating: "承認は未確定。条件を維持する。", count: 20),
      keyPoints: ["予算150万円"], decisions: [], openQuestions: ["承認日"], transcript: transcript,
      privacy: RecordPrivacy(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))) }
    var copyMS: [Double] = [], encodeMS: [Double] = [], sqliteMS: [Double] = [], totalMS: [Double] = []
    var before = rusage()
    precondition(getrusage(RUSAGE_SELF, &before) == 0)
    for trial in 0..<sampleCount {
      try autoreleasepool {
        let start = ContinuousClock.now
        var candidate = meetings
        candidate[count - 1].summary += "変更試行\(trial)"
        let copied = ContinuousClock.now
        let data = try JSONEncoder().encode(candidate)
        let encoded = ContinuousClock.now
        try store.applyBatch(writes: [("memoraMeetings", data), ("memoraTasks", Data("[]".utf8)),
          ("memoraPendingSummaryJobs", Data("[]".utf8))], removing: [])
        let saved = ContinuousClock.now
        copyMS.append(ms(start, copied)); encodeMS.append(ms(copied, encoded))
        sqliteMS.append(ms(encoded, saved)); totalMS.append(ms(start, saved))
        precondition(candidate[0] == meetings[0] && candidate[count - 1].transcript == transcript)
      }
    }
    var after = rusage()
    precondition(getrusage(RUSAGE_SELF, &after) == 0)
    let reopenStart = ContinuousClock.now
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    let opened = ContinuousClock.now
    guard case .data(let saved) = reopened.readOutcome("memoraMeetings") else { preconditionFailure("No saved record") }
    let read = ContinuousClock.now
    let decoded = try JSONDecoder().decode([Meeting].self, from: saved)
    let decodeFinished = ContinuousClock.now
    var afterRead = rusage()
    precondition(getrusage(RUSAGE_SELF, &afterRead) == 0)
    precondition(decoded.count == count)
    precondition(zip(decoded.dropLast(), meetings.dropLast()).allSatisfy { $0.0 == $0.1 })
    var expectedLast = meetings[count - 1]
    expectedLast.summary += "変更試行\(sampleCount - 1)"
    precondition(decoded.last == expectedLast)
    let row: [String: Any] = ["records": count, "segmentsPerRecord": segmentCount, "samples": sampleCount, "jsonBytes": saved.count,
      "copy": stats(copyMS), "encode": stats(encodeMS), "sqliteAtomicBatch": stats(sqliteMS), "total": stats(totalMS),
      "processPeakRSSBytes": after.ru_maxrss,
      "processCPUms": cpu(after) - cpu(before),
      "warmReopen": ["openMS": ms(reopenStart, opened), "readMS": ms(opened, read),
        "decodeMS": ms(read, decodeFinished), "processPeakRSSBytes": afterRead.ru_maxrss]]
    print(String(decoding: try JSONSerialization.data(withJSONObject: row, options: .sortedKeys), as: UTF8.self))
    fflush(stdout)
  }

  static func ms(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let parts = start.duration(to: end).components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }
  static func cpu(_ usage: rusage) -> Double {
    Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000 + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
  }
  static func stats(_ values: [Double]) -> [String: Double] {
    let values = values.sorted()
    let p95Index = Int(ceil(Double(values.count) * 0.95)) - 1
    return ["medianMS": values[values.count / 2], "p95MS": values[p95Index], "maxMS": values[values.count - 1]]
  }
}

// No fixture record has media. Any unexpected media access fails closed.
enum MediaFiles {
  static func resolve(_ value: String) -> URL? { preconditionFailure("Unexpected media access") }
  static func reference(for url: URL) -> String? { preconditionFailure("Unexpected media access") }
  static func writePhoto(_ data: Data) -> String? { preconditionFailure("Unexpected media access") }
  static func deletePhoto(_ name: String) { preconditionFailure("Unexpected media access") }
}
