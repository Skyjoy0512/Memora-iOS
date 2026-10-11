import Foundation

struct HealthReviewSnapshot {
  var steps: Double?
  var sleepSeconds: TimeInterval?
  var workoutSeconds: TimeInterval?
  var workoutRecordCount: Int

  var stepCount: Int? {
    guard let steps, steps.isFinite, steps >= 0, steps < Double(Int.max) else { return nil }
    return Int(steps)
  }

  var hasData: Bool {
    stepCount != nil || sleepDuration != nil || workoutDuration != nil
  }

  var sleepDuration: TimeInterval? { Self.validDuration(sleepSeconds) }
  var workoutDuration: TimeInterval? { Self.validDuration(workoutSeconds) }

  private static func validDuration(_ seconds: TimeInterval?) -> TimeInterval? {
    guard let seconds, seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return nil }
    return seconds
  }

  static func mergedDuration(_ intervals: [DateInterval], within period: ReviewPeriod) -> TimeInterval {
    let clipped = intervals.compactMap { interval -> DateInterval? in
      let start = max(interval.start, period.start)
      let end = min(interval.end, period.end)
      return end > start ? DateInterval(start: start, end: end) : nil
    }.sorted { $0.start < $1.start }
    var total: TimeInterval = 0
    var active: DateInterval?
    for interval in clipped {
      if let previous = active {
        if interval.start <= previous.end {
          active = DateInterval(start: previous.start, end: max(previous.end, interval.end))
        } else {
          total += previous.duration
          active = interval
        }
      } else {
        active = interval
      }
    }
    return total + (active?.duration ?? 0)
  }
}
