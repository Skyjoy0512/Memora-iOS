import SwiftUI

enum CaptureAction: CaseIterable, Identifiable {
  case recording
  case importAudio
  case onlineMeeting
  case phoneCall

  var id: Self { self }

  /// The actions the ＋ menu shows; calling waits behind its flag.
  static var available: [CaptureAction] {
    allCases.filter { $0 != .phoneCall || FeatureFlags.isCallingEnabled }
  }

  var title: String {
    switch self {
    case .recording: "録音を開始"
    case .importAudio: "音声を取り込む"
    case .onlineMeeting: "オンライン会議"
    case .phoneCall: "電話をかける"
    }
  }

  var symbol: MemoraIcon {
    switch self {
    case .recording: .waveform
    case .importAudio: .squareAndArrowDown
    case .onlineMeeting: .video
    case .phoneCall: .phoneFill
    }
  }

  var detail: String {
    switch self {
    case .recording: "このiPhoneのマイクで録音します。"
    case .importAudio: "保存済みの音声ファイルを読み込みます。"
    case .onlineMeeting: "スピーカーで再生する会議の音声を録音します。"
    case .phoneCall: "通話の設定と接続を確認します。"
    }
  }
}
