import Foundation

extension MemoraModel {
  func calendarReadIsCurrent(_ snapshot: AICalendarReadSnapshot?) -> Bool {
    guard let snapshot else { return true }
    return currentTeamID == nil && !isRestoring && !isStoreProtected && snapshot.isValid
      && snapshot.revision == calendarContextRevision && CalendarService.access == .granted
      && integrationIsEnabled("calendar")
  }

}
