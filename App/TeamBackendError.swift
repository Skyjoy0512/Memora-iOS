import Foundation

enum TeamBackendError: LocalizedError {
  /// No cloud service is connected to this build yet.
  case notConfigured
  /// Creating a team needs the team plan.
  case requiresTeamPlan
  case invalidInviteCode
  case invalidTaskBoard

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "チームのクラウドはまだ接続されていません。接続されるまで、チームの作成と参加はできません。個人のファイルはこれまでどおりこの端末に保存されます。"
    case .requiresTeamPlan:
      "チームを作成するにはチームプランが必要です。"
    case .invalidInviteCode:
      "招待コードを確認してください。"
    case .invalidTaskBoard:
      "チーム課題の同期結果を確認できません。ワークスペースを確認して再読み込みしてください。変更は端末の個人タスクに保存していません。"
    }
  }
}
