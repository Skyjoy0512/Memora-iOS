import Foundation

@main struct PersonSummaryChecks {
  static func main() {
    let recent = PersonConversationSummary.Topic(id: UUID(), title: "提案の確認", date: .now, summary: "範囲を確認", decisions: ["継続", "期限を見直す"], unresolved: ["予算確認"])
    let older = PersonConversationSummary.Topic(id: UUID(), title: "初回打合せ", date: .distantPast, summary: "", decisions: ["継続"], unresolved: [])
    let summary = PersonConversationSummary(topics: [recent, older])
    precondition(summary.recentDecisions == ["期限を見直す"])
    precondition(summary.unresolvedTopics.map(\.id) == [recent.id])
    precondition(summary.overview.contains(recent.title))
    precondition(PersonConversationSummary(topics: []).recentDecisions.isEmpty)
    precondition(PersonConversationSummary(topics: [older]).latestSubstantiveTopic == nil)
    precondition(PersonConversationSummary(topics: [older, recent]).latestSubstantiveTopic?.id == recent.id)
    print("PersonSummaryChecks: passed (literal evidence changes, source IDs, unresolved, empty; no inference)")
  }
}
