import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case newMemo
  case onlineMeeting
  case phoneCall
  case newChat

  var id: Self { self }

  /// Full empty-state actions; calling waits behind its flag.
  static var available: [CaptureAction] {
    allCases.filter { $0 != .phoneCall || FeatureFlags.isCallingEnabled }
  }

  var title: String {
    switch self {
    case .recording: "録音する"
    case .importAudio: "音声を取り込む"
    case .newMemo: "ノートと資料を追加"
    case .onlineMeeting: "オンライン会議を録音"
    case .phoneCall: "電話をかける"
    case .newChat: "新しいチャット"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .recording: .waveform
    case .importAudio: .squareAndArrowDown
    case .newMemo: .squareAndPencil
    case .onlineMeeting: .video
    case .phoneCall: .phoneFill
    case .newChat: .sparkles
    }
  }

  var detail: String {
    switch self {
    case .recording: "このiPhoneのマイクで録音します。"
    case .importAudio: "保存済みの音声ファイルを読み込みます。"
    case .newMemo: "ノートを書いたり、リンク・ファイル・写真を追加できます。"
    case .onlineMeeting: "スピーカーで再生する会議の音声を録音します。"
    case .phoneCall: "通話の設定と接続を確認します。"
    case .newChat: "Ask AIで新しい会話を始めます。"
    }
  }
}
