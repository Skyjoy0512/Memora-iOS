import CryptoKit
import Foundation

enum SummaryJobFingerprint {
  static func make(_ meeting: Meeting) -> String? {
    let input = Input(title: meeting.title, date: meeting.createdAt, duration: meeting.duration,
      transcript: meeting.transcript, summary: meeting.summary, privacy: meeting.effectivePrivacy,
      projectID: meeting.spaceID, participantIDs: meeting.participantIDs,
      keyPoints: meeting.keyPoints, decisions: meeting.decisions, openQuestions: meeting.openQuestions)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(input) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct Input: Encodable {
    var title: String
    var date: Date
    var duration: TimeInterval
    var transcript: [TranscriptSegment]
    var summary: String
    var privacy: RecordPrivacy
    var projectID: UUID?
    var participantIDs: [UUID]?
    var keyPoints: [String]
    var decisions: [String]
    var openQuestions: [String]
  }
}
