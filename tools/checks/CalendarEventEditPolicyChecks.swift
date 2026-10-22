import Foundation

@main
struct CalendarEventEditPolicyChecks {
  static func main() {
    for granted in [false, true] {
      for writable in [false, true] {
        for cancelled in [false, true] {
          for owned in [false, true] {
            let allowed = CalendarEventEditPolicy.allowsEditing(hasFullAccess: granted,
              calendarAllowsChanges: writable, isCancelled: cancelled, isOwnedByCurrentUser: owned)
            precondition(allowed == (granted && writable && !cancelled && owned))
          }
        }
      }
    }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let end = start.addingTimeInterval(3_600)
    precondition(CalendarEventEditPolicy.matchesOccurrence(id: "recurrence", start: start, end: end,
      expectedID: "recurrence", expectedStart: start, expectedEnd: end))
    precondition(!CalendarEventEditPolicy.matchesOccurrence(id: "recurrence", start: start.addingTimeInterval(86_400), end: end.addingTimeInterval(86_400),
      expectedID: "recurrence", expectedStart: start, expectedEnd: end))
    precondition(!CalendarEventEditPolicy.matchesOccurrence(id: "other", start: start, end: end,
      expectedID: "recurrence", expectedStart: start, expectedEnd: end))
    precondition(!CalendarEventEditPolicy.matchesOccurrence(id: "", start: start, end: end,
      expectedID: "", expectedStart: start, expectedEnd: end))
    precondition(!CalendarEventEditPolicy.matchesOccurrence(id: "recurrence", start: start, end: end.addingTimeInterval(60),
      expectedID: "recurrence", expectedStart: start, expectedEnd: end))
    print("CalendarEventEditPolicyChecks: passed (permission/writable/owner/cancelled gates, exact recurring occurrence and stale revision; EventKit UI save and account permissions require separate device validation)")
  }
}
