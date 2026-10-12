import Foundation

@main
struct AIWebSearchIntentChecks {
  static func main() {
    for text in ["箱根の観光情報を検索して", "iPhoneの最新価格を調べて", "京都のホテルをWebで検索して", "search for Hakone hotels"] {
      precondition(AIWebSearchIntent.route(text) == .search(text))
    }
    for text in ["過去の会議を検索して", "録音から議事録を調べて", "このプロジェクト内を検索して", "タスクを検索して", "今日のジャーナルを調べて", "保存した資料を検索して", "資料を検索して", "人物を調べて", "検索しないで説明して", "don't search the web", "こんにちは"] {
      precondition(AIWebSearchIntent.route(text) == .none)
    }
    precondition(AIWebSearchIntent.route("検索して") == .needsTopic)
    precondition(AIWebSearchIntent.route("検索して", previousQuery: "箱根の観光情報") == .search("箱根の観光情報"))
    precondition(AIWebSearchIntent.route("もっと詳しく", previousQuery: "箱根の観光情報") == .search("箱根の観光情報 もっと詳しく"))
    precondition(AIWebSearchIntent.route("もっと詳しく") == .none)
    precondition(AIWebSearchIntent.route("京都のホテル", requested: true) == .search("京都のホテル"))
    precondition(AIWebSearchIntent.route("検索しないで", requested: true) == .none)
    precondition(AIWebSearchIntent.route("会議用のホテルをWebで検索して") == .search("会議用のホテルをWebで検索して"))
    print("AIWebSearchIntentChecks: passed (natural search, internal scope, negation, missing topic, follow-ups, explicit toggle)")
  }
}
