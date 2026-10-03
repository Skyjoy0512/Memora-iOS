import Foundation

enum MCPClientError: LocalizedError {
  case invalidURL
  case unauthorized
  case server(String)
  case malformed

  var errorDescription: String? {
    switch self {
    case .invalidURL: "https のURLを入力してください。"
    case .unauthorized: "サーバーに認証を拒否されました。トークンを確認してください。"
    case .server(let message): "サーバーがエラーを返しました: \(message)"
    case .malformed: "サーバーの応答を読み取れませんでした。MCP（Streamable HTTP）のURLか確認してください。"
    }
  }
}
