import Foundation
import Observation

/// Holds the next calendar event for the Files screen. Keeping it out of the
/// view lets the screen decide whether to draw a row at all, so nothing empty is
/// left behind when no meeting is coming up.
@Observable
final class UpcomingMeetingStore {
  private(set) var meeting: UpcomingMeeting?

  /// Re-reads the next event, or clears it when the calendar is not available.
  func refresh() async {
    guard CalendarService.access == .granted else {
      meeting = nil
      return
    }
    meeting = await CalendarService.upcoming().first
  }
}
