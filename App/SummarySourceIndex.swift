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
  /// Entry lookup for reading a prompt line back to its segment. Kept apart
  /// from `byShortID`, which only maps ids that are unambiguous evidence.
  private var entriesByShortID: [String: Entry]
  private var entriesByID: [UUID: Entry]

  init(_ transcript: [TranscriptSegment]) {
    var speakers: [Speaker: String] = [:]
    var entries: [Entry] = []
    let counts = Dictionary(grouping: transcript, by: \.id).mapValues(\.count)
    var shortIDs: [String: UUID] = [:]
    var originals: [UUID: TranscriptSegment] = [:]
    var entryShortIDs: [String: Entry] = [:]
    var entryIDs: [UUID: Entry] = [:]
    for (index, segment) in transcript.enumerated() {
      let speaker = Speaker(name: segment.speaker, id: segment.speakerID, certain: segment.speakerIsCertain)
      let alias = speakers[speaker] ?? "A\(speakers.count + 1)"
      speakers[speaker] = alias
      let shortID = "S\(index + 1)"
      let entry = Entry(shortID: shortID, speakerAlias: alias, segment: segment)
      entries.append(entry)
      entryShortIDs[shortID] = entry
      if entryIDs[segment.id] == nil { entryIDs[segment.id] = entry }
      // Ambiguous UUIDs cannot become valid evidence through a short alias.
      if counts[segment.id] == 1 {
        shortIDs[shortID] = segment.id
        originals[segment.id] = segment
      }
    }
    self.entries = entries
    byShortID = shortIDs
    byOriginalID = originals
    entriesByShortID = entryShortIDs
    entriesByID = entryIDs
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

  struct Unit {
    var prefix: String
    var text: String
    var beginsBoundary = false
    var line: String { prefix + text }
  }

  func units(hasTimestamps: Bool, compact: Bool) -> [Unit] {
    var previous: Entry?
    return entries.compactMap { entry in
      guard !entry.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      let time = entry.segment.timestamp
      let stamp = hasTimestamps && time.isFinite && time >= 0 && time < Double(Int.max)
        ? MemoraFormat.duration(time) : "時刻不明"
      let identity = compact ? "\(entry.shortID) \(entry.speakerAlias)" :
        "[segmentID=\(entry.segment.id.uuidString)] \(entry.segment.speaker)"
      let boundary = previous.map { $0.speakerAlias != entry.speakerAlias ||
        (hasTimestamps && time - ($0.segment.endTime ?? $0.segment.timestamp) >= 30) } ?? false
      previous = entry
      return Unit(prefix: "[\(stamp)] \(identity): ", text: entry.segment.text, beginsBoundary: boundary)
    }
  }

  func lines(hasTimestamps: Bool) -> [String] { units(hasTimestamps: hasTimestamps, compact: true).map(\.line) }

  /// The text a part's lines carry after their identity, keyed by segment.
  /// Reference validation looks a quote up here instead of searching every line
  /// for every reference.
  func lineContents(inPart lines: [String], compact: Bool) -> [UUID: Substring] {
    var contents: [UUID: Substring] = [:]
    contents.reserveCapacity(lines.count)
    for line in lines {
      guard let entry = entry(forLine: line, compact: compact),
            contents[entry.segment.id] == nil,
            let range = line.range(of: Self.marker(for: entry, compact: compact)) else { continue }
      contents[entry.segment.id] = line[range.upperBound...]
    }
    return contents
  }

  /// The identity a unit line starts with, once the timestamp bracket is passed.
  static func marker(for entry: Entry, compact: Bool) -> String {
    compact ? "] \(entry.shortID) \(entry.speakerAlias): "
      : "] [segmentID=\(entry.segment.id.uuidString)] "
  }

  /// Reads the entry a unit line came from: `[mm:ss] [segmentID=…] 話者:` or
  /// `[mm:ss] S12 A1:`. A line that does not carry a readable identity has none.
  func entry(forLine line: String, compact: Bool) -> Entry? {
    guard let close = line.firstIndex(of: "]") else { return nil }
    var rest = line[line.index(after: close)...]
    if rest.first == " " { rest = rest.dropFirst() }
    if compact {
      guard let space = rest.firstIndex(of: " ") else { return nil }
      return entriesByShortID[String(rest[..<space])]
    }
    guard rest.hasPrefix("[segmentID="), let end = rest.firstIndex(of: "]") else { return nil }
    let start = rest.index(rest.startIndex, offsetBy: 11)
    guard start < end, let id = UUID(uuidString: String(rest[start..<end])) else { return nil }
    return entriesByID[id]
  }

  /// The segments a part's lines were written from, in the order they appear.
  ///
  /// A line starts with the identity the unit was given, so the segment is a
  /// lookup rather than a search: comparing every line against every segment
  /// took 0.75 s for a two-hour transcript, on every part of every summary.
  func segments(inPart lines: [String], compact: Bool) -> [TranscriptSegment] {
    var found: [TranscriptSegment] = []
    var seen: Set<UUID> = []
    found.reserveCapacity(lines.count)
    for line in lines {
      guard let entry = entry(forLine: line, compact: compact),
            seen.insert(entry.segment.id).inserted else { continue }
      found.append(entry.segment)
    }
    return found
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
