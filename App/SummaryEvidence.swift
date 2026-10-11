import Foundation

enum SummaryEvidence {
  static func matches(items: [String], transcript: [TranscriptSegment], duration: TimeInterval) -> [String: TranscriptSegment] {
    guard duration.isFinite, duration >= 0, duration < Double(Int.max) else { return [:] }
    let segments = transcript.filter { $0.timestamp.isFinite && $0.timestamp >= 0 && $0.timestamp <= duration }
      .map { (segment: $0, text: normalized($0.text)) }
    var result: [String: TranscriptSegment] = [:]
    for item in items {
      let statement = normalized(item)
      guard statement.count >= 8 else { continue }
      let matches = segments.filter { $0.text.contains(statement) }
      if matches.count == 1 { result[item] = matches[0].segment }
    }
    return result
  }

  private static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
      .replacingOccurrences(of: "**", with: "")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: "。"))
  }
}
