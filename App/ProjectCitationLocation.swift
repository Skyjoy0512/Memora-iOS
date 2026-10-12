import Foundation

enum ProjectCitationLocation {
  static func pageIndex(_ page: Int, count: Int) -> Int? {
    guard page > 0, page <= count else { return nil }
    return page - 1
  }

  static func playbackTime(_ time: TimeInterval?) -> TimeInterval? {
    guard let time, time.isFinite, time >= 0, time <= 7 * 24 * 60 * 60 else { return nil }
    return time
  }
}
