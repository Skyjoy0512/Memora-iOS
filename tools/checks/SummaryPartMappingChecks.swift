import Foundation

/// Checks that a summary part's lines map back to the same segments the old
/// line-by-line search found, and reports what each way costs on a two-hour
/// transcript.
@main
enum SummaryPartMappingChecks {
  static func main() throws {
    setvbuf(stdout, nil, _IONBF, 0)
    for (segments, compact) in [(120, false), (2_400, false), (2_400, true)] {
      let transcript = makeTranscript(segments)
      let index = SummarySourceIndex(transcript)
      let units = index.units(hasTimestamps: true, compact: compact)
      let part = units.map(\.line)

      // The search this replaced: every entry tested against every line.
      let expected = index.entries.filter { entry in
        let marker = compact ? "] \(entry.shortID) \(entry.speakerAlias): " : "] [segmentID=\(entry.segment.id.uuidString)] "
        return part.contains { line in
          guard let end = line.firstIndex(of: "]") else { return false }
          return line[end...].hasPrefix(marker)
        }
      }.map(\.segment)

      let found = index.segments(inPart: part, compact: compact)
      precondition(found.map(\.id) == expected.map(\.id),
                   "parts map to different segments at \(segments) compact=\(compact)")

      var searchTimes: [Double] = []
      var lookupTimes: [Double] = []
      for _ in 0..<3 {
        searchTimes.append(time {
          _ = index.entries.filter { entry in
            let marker = compact ? "] \(entry.shortID) \(entry.speakerAlias): " : "] [segmentID=\(entry.segment.id.uuidString)] "
            return part.contains { line in
              guard let end = line.firstIndex(of: "]") else { return false }
              return line[end...].hasPrefix(marker)
            }
          }
        })
        lookupTimes.append(time { _ = index.segments(inPart: part, compact: compact) })
      }
      print("{\"segments\":\(segments),\"compact\":\(compact),\"searchMS\":\(round(searchTimes.sorted()[1] * 100) / 100),\"lookupMS\":\(round(lookupTimes.sorted()[1] * 100) / 100)}")
    }

    // A line that does not carry a readable identity contributes nothing rather
    // than matching the wrong segment.
    let index = SummarySourceIndex(makeTranscript(4))
    precondition(index.segment(forLine: "[00:00] 話者1: 本文", compact: false) == nil)
    precondition(index.segment(forLine: "本文だけ", compact: true) == nil)
    precondition(index.segment(forLine: "[00:00] S99 A1: 本文", compact: true) == nil)
    precondition(index.segment(forLine: "[00:00] S2 A1: 本文", compact: true) != nil)
    print("Summary part mapping: same segments as the search, by identity lookup.")
  }

  private static func makeTranscript(_ count: Int) -> [TranscriptSegment] {
    (0..<count).map { index in
      TranscriptSegment(id: UUID(), speaker: "話者\(index % 3 + 1)", speakerIsCertain: true,
                        timestamp: Double(index) * 30,
                        text: "これは\(index)番目の確認用の発言です。決定事項と担当を確認します。",
                        endTime: Double(index) * 30 + 28)
    }
  }

  private static func time(_ block: () -> Void) -> Double {
    let start = ContinuousClock.now
    block()
    let end = ContinuousClock.now
    let parts = start.duration(to: end).components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }
}
