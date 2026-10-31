import Foundation

enum CommunityError: LocalizedError {
  case unconfigured, loginRequired, invalidContent, server(String), saveFailed
  var errorDescription: String? {
    switch self {
    case .unconfigured: "コミュニティの公開サービスはまだ接続されていません。"
    case .loginRequired: "コミュニティにログインしてください。"
    case .invalidContent: "共有する内容や対応するツールを確認してください。"
    case .server(let message): message
    case .saveFailed: "保存できませんでした。内容は追加されていません。"
    }
  }
}
