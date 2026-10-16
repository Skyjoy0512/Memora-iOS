import Foundation

/// Everything the records say about one person: the meetings they were in or
/// spoke in, what they took on, what was decided with them, and where the
/// journal mentions them. Built from the records, nothing inferred.
struct PersonMemory {
  struct Decision: Hashable {
    var meetingID: UUID
    var meetingTitle: String
    var date: Date
    var text: String
  }

  var person: Person
  /// Newest first.
  var meetings: [Meeting]
  /// A selected assignee is evidence of assignment, not proof of a spoken promise.
  var assignedTasks: [MemoraTask]
  /// Open tasks from meetings with them that are assigned to someone else or
  /// no one: what is still owed between you.
  var sharedTasks: [MemoraTask]
  /// Newest first, a few per meeting.
  var decisions: [Decision]
  var journalEntries: [LifeLogEntry]
  var nameMatchedTasks: [MemoraTask] = []
  var nameMatchedJournalEntries: [LifeLogEntry] = []

  var conversationSummary: PersonConversationSummary {
    PersonConversationSummary(topics: meetings.prefix(30).map { meeting in
      .init(id: meeting.id, title: meeting.displayTitle, date: meeting.createdAt,
        summary: String(meeting.summaryPreview.prefix(500)), decisions: meeting.decisions, unresolved: meeting.openQuestions)
    })
  }

  var lastMet: Date? {
    meetings.first?.createdAt
  }
}
