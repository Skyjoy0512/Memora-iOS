import Foundation

/// Query-local task grouping preserves scores and order without a task scan
/// for every meeting. It never caches permissions or content across requests.
enum MeetingRanking {
  static func rank(meetings: [Meeting], words: [String], tasks: [MemoraTask] = []) -> [Meeting] {
    guard !words.isEmpty else {
      return Array(meetings.sorted { $0.createdAt > $1.createdAt }.prefix(8))
    }

    let tasksByMeeting = Dictionary(grouping: tasks) { $0.meetingID }

    func score(of meeting: Meeting) -> Int {
      var total = 0
      for word in words where meeting.title.localizedCaseInsensitiveContains(word) {
        total += 3
      }
      let supporting = (
        meeting.decisions + meeting.openQuestions
          + (tasksByMeeting[meeting.id] ?? []).map(\.title)
      ).joined(separator: "\n")
      for word in words where supporting.localizedCaseInsensitiveContains(word) {
        total += 2
      }
      let body = ([meeting.notes, meeting.summary] + meeting.transcript.map(\.text))
        .joined(separator: "\n")
      for word in words where body.localizedCaseInsensitiveContains(word) {
        total += 1
      }
      return total
    }

    let matched = meetings
      .compactMap { meeting -> (meeting: Meeting, score: Int)? in
        let value = score(of: meeting)
        return value > 0 ? (meeting, value) : nil
      }
      .sorted { ($0.score, $0.meeting.createdAt) > ($1.score, $1.meeting.createdAt) }
      .prefix(8)
      .map(\.meeting)
    return matched.isEmpty
      ? Array(meetings.sorted { $0.createdAt > $1.createdAt }.prefix(8))
      : Array(matched)
  }

}
