import Foundation

/// A pill above the file list that narrows it by processing state.
enum MeetingFilter: String, CaseIterable, Identifiable {
  case all
  case ready
  case inProgress
  case needsAttention

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "すべて"
    case .ready: "整理済み"
    case .inProgress: "処理中"
    case .needsAttention: "要対応"
    }
  }

  func matches(_ status: MeetingStatus) -> Bool {
    switch self {
    case .all:
      true
    case .ready:
      status == .ready
    case .inProgress:
      switch status {
      case .waitingForTranscription, .waitingForSummary, .importing, .transcribing, .organizing:
        true
      default:
        false
      }
    case .needsAttention:
      switch status {
      case .partialFailure, .failed:
        true
      default:
        false
      }
    }
  }
}
