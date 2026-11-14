import Foundation

/// A source-linked view of saved facts; no model call or persistent summary cache.
struct PersonConversationSummary {
  struct Topic: Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var summary: String
    var decisions: [String]
    var unresolved: [String]
  }
  var topics: [Topic]

  var latestSubstantiveTopic: Topic? {
    topics.first { !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  var overview: String {
    guard let recent = topics.first else { return "参加者として紐づいた記録はまだありません。" }
    return "最近の記録は「\(recent.title)」（\(recent.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP"))))）です。" +
      (recent.summary.isEmpty ? "" : "\n" + recent.summary)
  }

  var unresolvedTopics: [Topic] { topics.filter { !$0.unresolved.isEmpty } }

  /// Only a literal change in saved decisions is shown; its meaning is not inferred.
  var recentDecisions: [String] {
    guard let recent = topics.first else { return [] }
    let earlier = Set(topics.dropFirst().flatMap(\.decisions))
    return recent.decisions.filter { !earlier.contains($0) }
  }
}
