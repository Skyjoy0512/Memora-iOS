import Foundation

struct Meeting: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var createdAt: Date
  var duration: TimeInterval
  var source: MeetingSource
  var status: MeetingStatus
  var summary: String
  var keyPoints: [String]
  var decisions: [String]
  var openQuestions: [String]
  var transcript: [TranscriptSegment]
  var spaceID: UUID?
  var audioURL: URL?
  var notes = ""
}

enum MeetingSource: String, Hashable, Codable {
  case recording
  case importFile

  var label: String {
    switch self {
    case .recording:
      "録音"
    case .importFile:
      "インポート"
    }
  }
}

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
    case .importing(let progress):
      "読み込み \(Int(progress * 100))%"
    case .transcribing(let progress):
      "文字起こし \(Int(progress * 100))%"
    case .organizing:
      "整理中"
    case .ready:
      "整理済み"
    case .partialFailure:
      "一部未完了"
    case .failed:
      "要確認"
    }
  }

  var symbol: String {
    switch self {
    case .waitingForTranscription:
      "waveform.badge.plus"
    case .waitingForSummary:
      "sparkles"
    case .importing:
      "arrow.down.doc"
    case .transcribing:
      "text.bubble"
    case .organizing:
      "sparkles"
    case .ready:
      "checkmark"
    case .partialFailure:
      "exclamationmark.triangle"
    case .failed:
      "arrow.clockwise"
    }
  }
}
