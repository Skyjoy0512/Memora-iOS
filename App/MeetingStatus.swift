import Foundation

enum MeetingStatus: Hashable, Codable {
  case waitingForTranscription
  case waitingForSummary
  case importing(Double)
  case transcribing(Double)
  case organizing(String)
  case ready
  case partialFailure(String)
  case failed(String)

  var shortLabel: String {
    switch self {
    case .waitingForTranscription:
      "未処理"
    case .waitingForSummary:
      "要約待ち"
    case .importing:
      "準備中"
    case .transcribing:
      "準備中"
    case .organizing:
      "準備中"
    case .ready:
      "整理済み"
    case .partialFailure:
      "一部未完了"
    case .failed:
      "要確認"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .waitingForTranscription:
      .waveformBadgePlus
    case .waitingForSummary:
      .sparkles
    case .importing:
      .arrowDownDoc
    case .transcribing:
      .textBubble
    case .organizing:
      .sparkles
    case .ready:
      .checkmark
    case .partialFailure:
      .exclamationmarkTriangle
    case .failed:
      .arrowClockwise
    }
  }
}
