import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case newMemo
  case onlineMeeting
  case phoneCall
  case newChat

  var id: Self { self }

  /// The actions the ＋ menu shows; calling waits behind its flag.
  static var available: [CaptureAction] {
    allCases.filter { $0 != .phoneCall || FeatureFlags.isCallingEnabled }
  }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "ファイルをインポート"
    case .newMemo: "メモを作成"
    case .onlineMeeting: "オンライン会議"
    case .phoneCall: "電話をかける"
    case .newChat: "新規チャット"
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
    case .newMemo: "思いついたことを今すぐ残します。"
    case .onlineMeeting: "スピーカーで再生する会議の音声を録音します。"
    case .phoneCall: "通話の設定と接続を確認します。"
    case .newChat: "Ask AIで新しい会話を始めます。"
    }
  }
}
