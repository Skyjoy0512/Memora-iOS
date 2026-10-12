import Foundation

enum AIWebSearchIntent {
  enum Route: Equatable { case none, needsTopic, search(String) }

  static func route(_ question: String, requested: Bool = false, previousQuery: String? = nil) -> Route {
    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = text.lowercased()
    let negations = ["検索しない", "検索しなく", "検索せず", "検索不要", "検索してはいけない", "調べない", "don't search", "do not search"]
    guard !negations.contains(where: lowered.contains) else { return .none }
    let external = ["webで", "web検索", "ウェブ", "ネットで", "インターネット", "オンラインで", "search the web", "deep research", "ディープリサーチ"]
      .contains(where: lowered.contains)
    let internalWords = ["録音", "文字起こし", "ジャーナル", "タスク", "会議", "プロジェクト", "資料", "人物", "日記", "保存した", "保存済み", "メモ", "メール", "gmail", "この記録", "自分の記録"]
    if !requested && !external && internalWords.contains(where: lowered.contains) { return .none }
    let asks = ["検索して", "検索お願い", "検索してください", "検索をお願い", "調べて", "調べてください", "search for", "look up", "find online"]
    let follows = ["もっと詳しく", "詳しく調べて", "別の情報も検索して", "他の情報も調べて", "続けて検索して"]
    let isFollowUp = follows.contains(lowered)
    guard requested || external || asks.contains(where: lowered.contains) || (previousQuery != nil && isFollowUp) else { return .none }
    let bare = ["検索して", "検索してください", "検索お願い", "web検索", "webで検索して", "ウェブで検索して", "調べて", "search the web"]
    if bare.contains(lowered) {
      return previousQuery.map { .search($0) } ?? .needsTopic
    }
    if isFollowUp, let previousQuery {
      return .search(String(previousQuery.prefix(500)) + " " + text)
    }
    return text.isEmpty ? .needsTopic : .search(text)
  }
}
