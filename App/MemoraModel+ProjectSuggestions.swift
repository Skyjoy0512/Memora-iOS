import Foundation

// Suggesting a project for a record that is in none, from what the records
// share: a calendar series, a meeting name, the people in it.
extension MemoraModel {
  private static let dismissedSuggestionsKey = "memora.projectSuggestion.dismissed"

  /// Projects ranked by evidence, strongest first. Empty when nothing links the
  /// record to any project, so no suggestion is made up.
  func projectSuggestions(for meeting: Meeting) -> [ProjectSuggestion] {
    guard meeting.spaceID == nil, !spaces.isEmpty,
          !dismissedSuggestionIDs.contains(meeting.id.uuidString) else { return [] }
    let key = Self.seriesKey(meeting.displayTitle)
    let people = Set(meeting.participantIDs ?? [])

    return spaces.compactMap { space -> ProjectSuggestion? in
      let filed = meetings.filter { $0.spaceID == space.id && $0.id != meeting.id }
      var score = 0
      var reasons: [String] = []

      if let eventID = meeting.calendarEventID, filed.contains(where: { $0.calendarEventID == eventID }) {
        score += 3
        reasons.append("同じカレンダーの定例の記録が入っています")
      } else if key.count >= 3, let same = filed.first(where: { Self.seriesKey($0.displayTitle) == key }) {
        score += 2
        reasons.append("同じ名前の会議「\(same.displayTitle)」が入っています")
      }

      let shared = people.intersection(filed.flatMap { $0.participantIDs ?? [] })
      if !shared.isEmpty {
        score += min(shared.count, 2)
        let names = shared.compactMap { person(id: $0)?.name }.prefix(2)
        reasons.append("\(names.joined(separator: "・"))さんの記録が入っています")
      }

      let spaceKey = Self.seriesKey(space.name)
      if spaceKey.count >= 3, key.contains(spaceKey) {
        score += 1
        reasons.append("会議名にプロジェクト名が含まれています")
      }

      guard score >= 2 else { return nil }
      return ProjectSuggestion(space: space, signal: min(score, 3), reasons: reasons)
    }
    .sorted { $0.signal > $1.signal }
  }

  /// Keeps the suggestion from coming back for this record.
  func dismissProjectSuggestion(for meetingID: UUID) {
    var dismissed = dismissedSuggestionIDs
    dismissed.insert(meetingID.uuidString)
    UserDefaults.standard.set(Array(dismissed), forKey: Self.dismissedSuggestionsKey)
    dismissedSuggestionRevision += 1
  }

  private var dismissedSuggestionIDs: Set<String> {
    _ = dismissedSuggestionRevision
    return Set(UserDefaults.standard.stringArray(forKey: Self.dismissedSuggestionsKey) ?? [])
  }
}
