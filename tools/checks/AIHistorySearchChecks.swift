import Foundation

@main
struct AIHistorySearchChecks {
  static func main() {
    let first = AIConversationEntry(id: UUID(), question: "企画の予算は？", answer: "ABCの回答",
      scopeLabel: "開発プロジェクト", createdAt: .now)
    let second = AIConversationEntry(id: UUID(), question: "別の質問", answer: "企画の結論です",
      scopeLabel: "営業", createdAt: .now)
    let entries = [first, second]
    precondition(AIHistorySearch.matching(entries, query: "").map(\.id) == entries.map(\.id))
    precondition(AIHistorySearch.matching(entries, query: "　 \n").map(\.id) == entries.map(\.id))
    precondition(AIHistorySearch.matching(entries, query: "企画").count == 2)
    precondition(AIHistorySearch.matching(entries, query: "開発").map(\.id) == [first.id])
    precondition(AIHistorySearch.matching(entries, query: "ａｂｃ").map(\.id) == [first.id])
    precondition(AIHistorySearch.matching(entries, query: "企画　予算").map(\.id) == [first.id])
    precondition(AIHistorySearch.matching(entries, query: "企画 ABC").map(\.id) == [first.id])
    precondition(AIHistorySearch.matching(entries, query: "存在しない言葉").isEmpty)
    let filtered = AIHistorySearch.matching(entries, query: "営業")
    precondition(filtered.first?.id == second.id && filtered.first?.id != entries.first?.id)
    precondition(AIHistorySearch.matching([], query: "企画").isEmpty)
    print("AI history search checks passed")
  }
}
