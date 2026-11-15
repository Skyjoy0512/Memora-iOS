import Foundation

enum SummaryRetryDelay: Equatable {
  case seconds(TimeInterval)
  case untilRestart

  static func parse(_ header: String?, date: Date) -> Self {
    guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return .seconds(60) }
    if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
      guard let seconds = Double(value), seconds.isFinite, seconds <= 31_536_000 else { return .untilRestart }
      return .seconds(seconds)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.isLenient = false
    formatter.twoDigitStartDate = formatter.calendar.date(byAdding: .year, value: -50, to: date)
    for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
      formatter.dateFormat = format
      if let deadline = formatter.date(from: value) {
        let seconds = max(0, deadline.timeIntervalSince(date))
        return seconds <= 31_536_000 ? .seconds(seconds) : .untilRestart
      }
    }
    return .seconds(60)
  }
}
