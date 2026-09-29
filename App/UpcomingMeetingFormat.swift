import Foundation

/// How a coming event's day and time read, shared by the card and the sheet
/// that asks how to record it.
enum UpcomingMeetingFormat {
  /// 今日 / 明日 for the next two days, otherwise the date and weekday.
  static func day(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "今日" }
    if calendar.isDateInTomorrow(date) { return "明日" }
    return date.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))
  }

  static func timeRange(_ meeting: UpcomingMeeting) -> String {
    let start = meeting.start.formatted(date: .omitted, time: .shortened)
    let end = meeting.end.formatted(date: .omitted, time: .shortened)
    return "\(start)–\(end)"
  }
}
