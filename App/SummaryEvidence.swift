import CryptoKit
import Foundation

enum SummaryEvidence {
  static func fingerprint(_ transcript: [TranscriptSegment]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(transcript) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func validatedLinks(_ evidence: [GeneratedSummaryEvidence], sectionTitle: String,
                             recordID: UUID, transcript: [TranscriptSegment], duration: TimeInterval) -> [SummaryEvidenceLink] {
    guard duration.isFinite, duration >= 0, duration < Double(Int.max) else { return [] }
    var seen: Set<UUID> = []
    return evidence.prefix(64).compactMap { reference in
      guard reference.sectionTitle == sectionTitle,
            let id = UUID(uuidString: reference.sourceSegmentID),
            transcript.filter({ $0.id == id }).count == 1,
            let segment = transcript.first(where: { $0.id == id }),
            segment.timestamp.isFinite, segment.timestamp >= 0, segment.timestamp <= duration,
            reference.quote.count >= 8, reference.quote.count <= 2_000,
            segment.text.contains(reference.quote), seen.insert(id).inserted else { return nil }
      return SummaryEvidenceLink(sourceRecordID: recordID, sourceSegmentID: id, sourceText: segment.text)
    }
  }

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
