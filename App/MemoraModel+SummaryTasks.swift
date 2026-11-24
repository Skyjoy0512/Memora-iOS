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
    // A verified voice lets an action the summary credited to the person be
    // confirmed or ruled out; without one, the name-based rule is unchanged.
    let record = meeting(id: meetingID)
    for action in actions {
      let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, existing.insert(SummaryResponseParser.taskKey(title)).inserted else { continue }
      let spokenOwner = SummaryActionItem.normalized(action.owner)
      let ownedByMe = record.flatMap {
        speakerActionOwnership(owner: spokenOwner, title: title, in: $0)
      }
      added.append(MemoraTask(
        id: UUID(),
        title: title,
        meetingID: meetingID,
        assignee: ownedByMe == true ? nil : spokenOwner,
        dueDate: action.dueDate(relativeTo: meetingDate),
        isCompleted: false,
        detail: action.detail,
        ownedByMe: ownedByMe
      ))
    }
    // Newest first, like a task added by hand, keeping the meeting's order.
    return added
  }
}
