import Foundation

enum CalendarEventEditPolicy {
  static func allowsEditing(hasFullAccess: Bool, calendarAllowsChanges: Bool,
                            isCancelled: Bool, isOwnedByCurrentUser: Bool) -> Bool {
    hasFullAccess && calendarAllowsChanges && !isCancelled && isOwnedByCurrentUser
  }

  static func matchesOccurrence(id: String, start: Date, end: Date,
                                expectedID: String, expectedStart: Date, expectedEnd: Date) -> Bool {
    !expectedID.isEmpty && id == expectedID && start == expectedStart && end == expectedEnd
      && start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && end >= start
  }
}
