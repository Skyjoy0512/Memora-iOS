import Foundation

struct IntegrationCatalog: Identifiable {
  var id: String
  var name: String
  var summary: String
  var permissions: String
  var isImplemented: Bool

  var aliases: [String] {
    switch id {
    case "gmail": ["Google Mail", "メール", "ジーメール"]
    case "calendar": ["Calendar", "予定", "カレンダー"]
    case "notion": ["ノーション", "ページ"]
    case "mcp": ["プラグイン", "連携", "server"]
    case "drive": ["ドライブ", "Google Drive"]
    case "github": ["ギットハブ", "Issue", "Pull Request"]
    default: []
    }
  }
  var toolNames: [String] {
    switch id {
    case "gmail": ["search_email", "read_email"]
    case "calendar": ["read_calendar", "create_calendar_event"]
    case "notion": ["save_to_notion", "search_records", "read_record"]
    default: []
    }
  }

  static var services: [IntegrationCatalog] {
    [
      .init(id: "gmail", name: "Gmail", summary: "メールを検索・閲覧します。送信はしません。", permissions: "読み取り専用。取得した内容は選択中のAIに渡されます。", isImplemented: true),
      .init(id: "calendar", name: "この端末のカレンダー", summary: "予定を確認し、承認した予定を登録します。", permissions: "登録前に内容を確認します。Google Calendarへの直接OAuth接続ではありません。", isImplemented: true),
      .init(id: "notion", name: "Notion", summary: "指定した親ページにページを作成します。", permissions: "作成前に内容を確認します。ページの検索・閲覧には未対応です。", isImplemented: true),
      .init(id: "mcp", name: "MCPサーバー", summary: "指定したリモートサーバーのツールを利用します。", permissions: "接続先・ツール・料金を確認してください。自動実行は確認済みの無料の読み取りのみです。", isImplemented: true),
      .init(id: "drive", name: "Google Drive", summary: "認証済みバックエンドが必要です。", permissions: "接続・ファイル取得は未実装です。", isImplemented: false),
      .init(id: "github", name: "GitHub", summary: "認証済みバックエンドが必要です。", permissions: "接続・Issue・Pull Requestの取得は未実装です。", isImplemented: false)
    ]
  }
}
