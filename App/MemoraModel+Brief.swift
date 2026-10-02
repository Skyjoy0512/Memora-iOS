import Foundation

// Recurring business meetings: what earlier occurrences left open, and filing
// a new recording where the last one went.
extension MemoraModel {
  /// Earlier records of the same meeting, newest first: those recorded from
  /// the same calendar series, or whose title matches once dates and numbers
  /// are set aside ("週次定例 10/2" and "週次定例 10/9").
  func earlierRecords(ofEventID eventID: String?, title: String) -> [Meeting] {
    let key = Self.seriesKey(title)
    return meetings
      .filter { meeting in
        if let eventID, meeting.calendarEventID == eventID { return true }
        // A generic two-character title (会議, 面談) is too common to tell
        // one series from another.
        return key.count >= 3 && Self.seriesKey(meeting.displayTitle) == key
      }
      .sorted { $0.createdAt > $1.createdAt }
  }

  /// A title with dates, numbers, brackets and spaces removed, so the
  /// occurrences of one meeting series compare equal.
  static func seriesKey(_ title: String) -> String {
    let ignored = CharacterSet.decimalDigits
      .union(.whitespacesAndNewlines)
      .union(.punctuationCharacters)
      .union(.symbols)
      .union(CharacterSet(charactersIn: "第回月日年（）【】「」"))
    return String(String.UnicodeScalarView(title.lowercased().unicodeScalars.filter { !ignored.contains($0) }))
  }

  /// What is still open going into an upcoming event, or nil when nothing
  /// earlier is known.
  func meetingBrief(for event: UpcomingMeeting) -> MeetingBrief? {
    let records = earlierRecords(ofEventID: event.id, title: event.title)
    guard let last = records.first else { return nil }
    let recordIDs = Set(records.map(\.id))
    let openTasks = tasks
      .filter { task in !task.isCompleted && task.meetingID.map(recordIDs.contains) == true }
      .prefix(8)
    return MeetingBrief(
      lastMeeting: last,
      recordCount: records.count,
      openTasks: Array(openTasks),
      openQuestions: Array(last.openQuestions.prefix(5)),
      decisions: Array(last.decisions.prefix(4))
    )
  }

  /// The project a new recording of this event belongs in: the one its last
  /// filed occurrence of the same calendar series went to, if that project
  /// still exists. Only the series counts here, never a title that merely
  /// looks alike, so nothing is filed into the wrong project.
  func recurringProjectID(forEventID eventID: String) -> UUID? {
    meetings
      .filter { $0.calendarEventID == eventID }
      .sorted { $0.createdAt > $1.createdAt }
      .lazy
      .compactMap(\.spaceID)
      .first { self.space(id: $0) != nil }
  }
}
