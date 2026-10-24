import Foundation

extension MemoraModel {
  /// Files a summary's actions in the tasks tab, tied to their record. An
  /// action whose title the record already has a task for is skipped, so
  /// generating again does not duplicate tasks or touch ones already edited.
  /// Owner and due date are only set when the meeting said them.
  @discardableResult
  func addExtractedTasks(_ actions: [SummaryActionItem], meetingID: UUID, meetingDate: Date) -> Int {
    let added = extractedTasks(actions, meetingID: meetingID, meetingDate: meetingDate)
    guard !added.isEmpty else { return 0 }
    return insertTasks(added) ? added.count : 0
  }

  func extractedTasks(_ actions: [SummaryActionItem], meetingID: UUID, meetingDate: Date) -> [MemoraTask] {
    var existing = Set(tasks(forMeeting: meetingID).map { SummaryResponseParser.taskKey($0.title) })
    var added: [MemoraTask] = []
    for action in actions {
      let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, existing.insert(SummaryResponseParser.taskKey(title)).inserted else { continue }
      added.append(MemoraTask(
        id: UUID(),
        title: title,
        meetingID: meetingID,
        assignee: SummaryActionItem.normalized(action.owner),
        dueDate: action.dueDate(relativeTo: meetingDate),
        isCompleted: false,
        detail: action.detail
      ))
    }
    // Newest first, like a task added by hand, keeping the meeting's order.
    return added
  }
}
