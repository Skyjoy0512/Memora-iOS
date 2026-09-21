import Foundation

extension MemoraModel {
  /// The records whose searchable text contains `query` and that pass every
  /// active filter.
  func searchMeetings(matching query: String, filters: SearchFilters) -> [Meeting] {
    let startedAt = Date()
    let cutOff = filters.period.cutOff()
    let results = meetings.filter { meeting in
      guard searchText(for: meeting).localizedCaseInsensitiveContains(query) else { return false }
      if let cutOff, meeting.createdAt < cutOff { return false }
      if let personID = filters.personID,
         !(meeting.participantIDs ?? []).contains(personID) {
        return false
      }
      if let spaceID = filters.spaceID, meeting.spaceID != spaceID { return false }
      if let status = filters.status, !status.matches(meeting.status) { return false }
      return true
    }
    performance.record(
      "検索（会議）",
      milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000,
      count: meetings.count
    )
    return results
  }

  /// Tasks that match the query. The period and person filters read the task's
  /// own due date and assignee, and the project filter reads the space of the
  /// record the task came from.
  func searchTasks(matching query: String, filters: SearchFilters) -> [MemoraTask] {
    let cutOff = filters.period.cutOff()
    let assigneeName = filters.personID.flatMap { person(id: $0)?.name }
    return tasks.filter { task in
      guard task.title.localizedCaseInsensitiveContains(query) else { return false }
      if let cutOff {
        guard let dueDate = task.dueDate, dueDate >= cutOff else { return false }
      }
      if let assigneeName {
        guard let assignee = task.assignee,
              assignee.compare(assigneeName, options: .caseInsensitive) == .orderedSame else {
          return false
        }
      }
      if let spaceID = filters.spaceID {
        guard let meetingID = task.meetingID, meeting(id: meetingID)?.spaceID == spaceID else {
          return false
        }
      }
      // A task is finished or it is not; the record-only states do not apply.
      switch filters.status {
      case .finished:
        if !task.isCompleted { return false }
      case .unfinished:
        if task.isCompleted { return false }
      case .processing, .needsAttention:
        return false
      case nil:
        break
      }
      return true
    }
  }
}
