import Foundation

/// What is still open from earlier meetings of the same series, gathered
/// before the next one starts. Built from the records alone, no model.
struct MeetingBrief {
  /// The latest earlier record of this meeting.
  var lastMeeting: Meeting
  /// How many earlier records were found in all.
  var recordCount: Int
  /// Unfinished tasks from those records.
  var openTasks: [MemoraTask]
  /// What the last meeting left undecided.
  var openQuestions: [String]
  /// What the last meeting decided.
  var decisions: [String]

  var isEmpty: Bool {
    openTasks.isEmpty && openQuestions.isEmpty && decisions.isEmpty
  }
}
