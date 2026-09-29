import Foundation
import Observation

/// Holds the coming calendar events for the Files screen. Keeping them out of
/// the view lets the screen decide whether to draw the row at all, so nothing
/// empty is left behind when no meeting is coming up.
@Observable
final class UpcomingMeetingStore {
  private(set) var meetings: [UpcomingMeeting] = []

  /// Re-reads the coming events, or clears them when the calendar is not
  /// available. Only assigned on change, so a refresh does not redraw the row.
  func refresh() async {
    guard CalendarService.access == .granted else {
      if !meetings.isEmpty { meetings = [] }
      return
    }
    let fresh = await CalendarService.upcoming(limit: 10)
    if fresh != meetings { meetings = fresh }
  }
}
