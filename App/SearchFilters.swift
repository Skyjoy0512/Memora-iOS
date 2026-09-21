import Foundation

/// What the search sheet narrows by. Every dimension defaults to "not
/// filtering", so an untouched set of filters matches everything the query did.
struct SearchFilters: Equatable {
  enum Period: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
      switch self {
      case .all: "すべて"
      case .today: "今日"
      case .week: "過去7日"
      case .month: "過去30日"
      case .year: "今年"
      }
    }

    /// The earliest date that still matches, or nil for no limit.
    func cutOff(from now: Date = .now, calendar: Calendar = .current) -> Date? {
      switch self {
      case .all: nil
      case .today: calendar.startOfDay(for: now)
      case .week: calendar.date(byAdding: .day, value: -7, to: now)
      case .month: calendar.date(byAdding: .day, value: -30, to: now)
      case .year: calendar.date(from: calendar.dateComponents([.year], from: now))
      }
    }
  }

  /// The one state filter both lists understand. A record is finished when it
  /// is ready; a task is finished when it is completed. The record-only states
  /// leave tasks out, because a task has no such state.
  enum Status: String, CaseIterable, Identifiable {
    case unfinished
    case finished
    case processing
    case needsAttention

    var id: String { rawValue }

    var title: String {
      switch self {
      case .unfinished: "未完了"
      case .finished: "完了"
      case .processing: "処理中"
      case .needsAttention: "要確認"
      }
    }

    func matches(_ status: MeetingStatus) -> Bool {
      switch self {
      case .unfinished: status != .ready
      case .finished: status == .ready
      case .processing:
        switch status {
        case .waitingForTranscription, .waitingForSummary, .importing, .transcribing, .organizing: true
        case .ready, .partialFailure, .failed: false
        }
      case .needsAttention:
        switch status {
        case .partialFailure, .failed: true
        case .waitingForTranscription, .waitingForSummary, .importing, .transcribing, .organizing, .ready: false
        }
      }
    }
  }

  var period: Period = .all
  var personID: UUID?
  var spaceID: UUID?
  var status: Status?

  var isActive: Bool {
    period != .all || personID != nil || spaceID != nil || status != nil
  }

  mutating func reset() {
    self = SearchFilters()
  }
}
