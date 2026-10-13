import Foundation

enum MCPClientError: LocalizedError {
  case invalidURL
  case unauthorized
  case server(String)
  case malformed
  case timeout

  var errorDescription: String? {
    switch self {
    case .invalidURL: "公開されたHTTPSの接続先を入力してください。ローカル・認証情報付き・リダイレクト先は利用できません。"
    case .unauthorized: "サーバーに認証を拒否されました。トークンを確認してください。"
    case .server(let message): "サーバーがエラーを返しました: \(message)"
    case .malformed: "サーバーの応答を読み取れませんでした。MCP（Streamable HTTP）のURLか確認してください。"
    case .timeout: "MCPの応答が時間内に届きませんでした。自動再実行はしていません。"
    }
  }
}
