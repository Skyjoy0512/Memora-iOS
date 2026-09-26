import Foundation

/// How the files list is drawn. Persisted, so it survives a restart.
enum FileListLayout: String, CaseIterable, Identifiable {
  case card
  case list

  var id: Self { self }

  var label: String {
    switch self {
    case .card: "カード"
    case .list: "リスト"
    }
  }
}

/// The order the files list is shown in.
enum FileListSort: String, CaseIterable, Identifiable {
  case newest
  case oldest
  case longest

  var id: Self { self }

  var label: String {
    switch self {
    case .newest: "新しい順"
    case .oldest: "古い順"
    case .longest: "長い順"
    }
  }
}

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
