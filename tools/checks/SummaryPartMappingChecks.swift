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

    // Reference validation: the same references are accepted, found by lookup.
    for (segments, compact) in [(1_200, false), (1_200, true)] {
      let transcript = makeTranscript(segments)
      let index = SummarySourceIndex(transcript)
      let part = index.units(hasTimestamps: true, compact: compact).map(\.line)
      let references = index.entries.prefix(256).map { entry in
        SummaryPartArtifact.Reference(
          sourceSegmentID: compact ? entry.shortID : entry.segment.id.uuidString,
          quote: String(entry.segment.text.prefix(12)))
      }
      let artifact = SummaryPartArtifact(notes: "確認", sourceReferences: references)

      // The search this replaced.
      func searchValidation() -> Bool {
        references.allSatisfy { reference in
          guard let id = index.originalID(for: reference.sourceSegmentID, allowShortIDs: compact),
                let entry = index.entries.first(where: { $0.segment.id == id }) else { return false }
          let marker = compact ? "] \(entry.shortID) \(entry.speakerAlias): " : "] [segmentID=\(id.uuidString)] "
          return index.validates(id: reference.sourceSegmentID, quote: reference.quote, allowShortIDs: compact) &&
            part.contains { line in
              guard line.hasPrefix("["), let end = line.firstIndex(of: "]"),
                    line[end...].hasPrefix(marker) else { return false }
              let content = line.index(end, offsetBy: marker.count)
              return line[content...].contains(reference.quote)
            }
        }
      }
      precondition(searchValidation())
      precondition(artifact.validated(in: index, part: part, compact: compact))

      var searchTimes: [Double] = []
      var lookupTimes: [Double] = []
      for _ in 0..<3 {
        searchTimes.append(time { precondition(searchValidation()) })
        lookupTimes.append(time { precondition(artifact.validated(in: index, part: part, compact: compact)) })
      }
      print("{\"validation\":true,\"segments\":\(segments),\"compact\":\(compact),\"searchMS\":\(round(searchTimes.sorted()[1] * 100) / 100),\"lookupMS\":\(round(lookupTimes.sorted()[1] * 100) / 100)}")
    }

    // A line that does not carry a readable identity contributes nothing rather
    // than matching the wrong segment.
    let index = SummarySourceIndex(makeTranscript(4))
    precondition(index.entry(forLine: "[00:00] 話者1: 本文", compact: false) == nil)
    precondition(index.entry(forLine: "本文だけ", compact: true) == nil)
    precondition(index.entry(forLine: "[00:00] S99 A1: 本文", compact: true) == nil)
    precondition(index.entry(forLine: "[00:00] S2 A1: 本文", compact: true) != nil)
    // The content after the identity is what a quote is matched against.
    let contents = index.lineContents(inPart: index.units(hasTimestamps: true, compact: true).map(\.line),
                                      compact: true)
    precondition(contents.count == 4 && contents.values.contains { $0.hasPrefix("これは") })
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
