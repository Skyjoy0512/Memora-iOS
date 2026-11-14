import Foundation

/// Whole utterances first, then sentence/whitespace boundaries for an utterance
/// too large for one request. Every character stays in chronological order.
enum SummaryInputPartition {
  static func make(_ units: [SummarySourceIndex.Unit], capacity: Int) -> Result<[[String]], AIAnswerFailure> {
    guard capacity >= 1 else { return .failure(.contextTooLarge) }
    guard !units.isEmpty else { return .success([]) }
    let total = units.reduce(0) { $0 + $1.prefix.utf8.count + $1.text.utf8.count + 1 }
    if total <= capacity { return .success([units.map(\.line)]) }
    var parts: [[String]] = [], current: [String] = [], used = 0
    for unit in units {
      let available = capacity - unit.prefix.utf8.count - 1
      guard available > 0, let bodies = slices(unit.text, capacity: available) else { return .failure(.contextTooLarge) }
      for body in bodies {
        let cost = unit.prefix.utf8.count + body.utf8.count + 1
        if !current.isEmpty && (used + cost > capacity || (unit.beginsBoundary && used >= capacity * 9 / 10)) {
          parts.append(current); current = []; used = 0
        }
        current.append(unit.prefix + body)
        used += cost
        guard parts.count < 512 else { return .failure(.executionLimit) }
      }
    }
    if !current.isEmpty { parts.append(current) }
    return .success(parts)
  }

  private static func slices(_ text: String, capacity: Int) -> [String]? {
    guard text.utf8.count > capacity else { return [text] }
    var result: [String] = [], start = text.startIndex
    while start < text.endIndex {
      var cursor = start, bytes = 0, preferred: String.Index?
      while cursor < text.endIndex {
        let next = text.index(after: cursor)
        let cost = text[cursor..<next].utf8.count
        if bytes + cost > capacity { break }
        bytes += cost
        let character = text[cursor]
        if bytes >= capacity / 2 && (character.isWhitespace || "。！？.!?".contains(character)) { preferred = next }
        cursor = next
      }
      guard cursor > start else { return nil }
      let end = cursor == text.endIndex ? cursor : (preferred ?? cursor)
      result.append(String(text[start..<end]))
      start = end
    }
    return result
  }
}
