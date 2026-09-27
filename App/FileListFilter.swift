import Foundation

/// A status filter for the files list.
enum FileListFilter: String, CaseIterable, Identifiable {
  case all
  case needsAttention
  case inProgress
  case done

  var id: Self { self }

  var label: String {
    switch self {
    case .all: "すべて"
    case .needsAttention: "要対応"
    case .inProgress: "処理中"
    case .done: "完了"
    }
  }

  func matches(_ status: MeetingStatus) -> Bool {
    switch self {
    case .all:
      true
    case .needsAttention:
      switch status {
      case .waitingForTranscription, .waitingForSummary, .failed, .partialFailure: true
      default: false
      }
    case .inProgress:
      switch status {
      case .importing, .transcribing, .organizing: true
      default: false
      }
    case .done:
      status == .ready
    }
  }
}
