import AppIntents

enum MemoraIntentFailure: Error, CustomLocalizedStringResourceConvertible {
  case recordingNotStarted, projectUnavailable, openAppToRecord

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .recordingNotStarted: "録音を開始できませんでした。Memoraでマイクの許可と録音の状態を確認してください。"
    case .projectUnavailable: "このプロジェクトは現在開けません。Memoraで所属と表示設定を確認してください。"
    case .openAppToRecord: "Memoraを開いてロックと保存状態を確認し、アプリ内から録音を開始してください。"
    }
  }
}
