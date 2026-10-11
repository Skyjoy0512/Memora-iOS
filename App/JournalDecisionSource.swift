import Foundation

struct JournalDecisionSource: Identifiable, Hashable {
  var meetingID: UUID
  var title: String
  var statement: String
  var timestamp: TimeInterval?

  var id: String { meetingID.uuidString + ":" + statement }

  static func build(meetings: [Meeting]) -> [JournalDecisionSource] {
    var seen: Set<String> = []
    return meetings.flatMap { meeting -> [JournalDecisionSource] in
      let matches = SummaryEvidence.matches(items: meeting.decisions, transcript: meeting.transcript, duration: meeting.duration)
      return meeting.decisions.compactMap { decision -> JournalDecisionSource? in
        let statement = JournalRecapWriter.excerpt(decision)
        guard !statement.isEmpty else { return nil }
        let source = JournalDecisionSource(meetingID: meeting.id, title: meeting.displayTitle,
          statement: statement, timestamp: matches[decision]?.timestamp)
        return seen.insert(source.id).inserted ? source : nil
      }
    }
  }
}
