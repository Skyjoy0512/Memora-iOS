import Foundation

struct SummaryEvidenceLink: Codable, Hashable {
  var sourceRecordID: UUID
  var sourceSegmentID: UUID
  var sourceText: String

  func resolves(recordID: UUID, transcript: [TranscriptSegment], duration: TimeInterval) -> Bool {
    guard duration.isFinite, duration >= 0, duration < Double(Int.max),
          transcript.filter({ $0.id == sourceSegmentID }).count == 1 else { return false }
    return sourceRecordID == recordID && transcript.contains {
      $0.id == sourceSegmentID && $0.text == sourceText
        && $0.timestamp.isFinite && $0.timestamp >= 0 && $0.timestamp <= duration
    }
  }
}
