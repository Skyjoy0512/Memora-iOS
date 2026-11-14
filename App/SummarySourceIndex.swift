import Foundation

/// Short references exist only in an immutable inference snapshot. Stored
/// evidence always uses the original IDs; prose and source text are never rewritten.
struct SummarySourceIndex {
  struct Entry {
    var shortID: String
    var speakerAlias: String
    var segment: TranscriptSegment
  }

  var entries: [Entry]
  private var byShortID: [String: UUID]
  private var byOriginalID: [UUID: TranscriptSegment]

  init(_ transcript: [TranscriptSegment]) {
    var speakers: [Speaker: String] = [:]
    var entries: [Entry] = []
    let counts = Dictionary(grouping: transcript, by: \.id).mapValues(\.count)
    var shortIDs: [String: UUID] = [:]
    var originals: [UUID: TranscriptSegment] = [:]
    for (index, segment) in transcript.enumerated() {
      let speaker = Speaker(name: segment.speaker, id: segment.speakerID, certain: segment.speakerIsCertain)
      let alias = speakers[speaker] ?? "A\(speakers.count + 1)"
      speakers[speaker] = alias
      let shortID = "S\(index + 1)"
      entries.append(Entry(shortID: shortID, speakerAlias: alias, segment: segment))
      // Ambiguous UUIDs cannot become valid evidence through a short alias.
      if counts[segment.id] == 1 {
        shortIDs[shortID] = segment.id
        originals[segment.id] = segment
      }
    }
    self.entries = entries
    byShortID = shortIDs
    byOriginalID = originals
  }

  var legend: String {
    var seen: Set<String> = []
    let speakers: [[String: Any]] = entries.compactMap { entry in
      guard seen.insert(entry.speakerAlias).inserted else { return nil }
      var value: [String: Any] = ["id": entry.speakerAlias, "name": entry.segment.speaker,
        "certain": entry.segment.speakerIsCertain]
      if let id = entry.segment.speakerID { value["speakerID"] = id }
      return value
    }
    let encoded = (try? JSONSerialization.data(withJSONObject: speakers, options: [.sortedKeys])) ?? Data()
    return "S番号はこの原文内のsegmentID。出典のsourceSegmentIDにはS番号をそのまま使う。A番号の話者対応: " +
      (String(data: encoded, encoding: .utf8) ?? "[]")
  }

  func lines(hasTimestamps: Bool) -> [String] {
    entries.filter { !$0.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { entry in
      let time = entry.segment.timestamp
      let stamp = hasTimestamps && time.isFinite && time >= 0 && time < Double(Int.max)
        ? MemoraFormat.duration(time) : "時刻不明"
      return "[\(stamp)] \(entry.shortID) \(entry.speakerAlias): \(entry.segment.text)"
    }
  }

  func originalID(for reference: String, allowShortIDs: Bool = true) -> UUID? {
    if allowShortIDs, let id = byShortID[reference] { return id }
    guard let id = UUID(uuidString: reference), byOriginalID[id] != nil else { return nil }
    return id
  }

  func validates(id: String, quote: String, allowShortIDs: Bool = true) -> Bool {
    guard (8...2_000).contains(quote.count), let original = originalID(for: id, allowShortIDs: allowShortIDs),
          let segment = byOriginalID[original] else { return false }
    return segment.text.contains(quote)
  }

  private struct Speaker: Hashable {
    var name: String
    var id: String?
    var certain: Bool
  }
}
