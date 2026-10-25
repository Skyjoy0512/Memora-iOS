import Foundation

enum MeetingQuestionSuggestions {
  static func make(summary: String, infographic: MeetingInfographic?) -> [String] {
    if let infographic { return infographic.content.questions }
    let extracted = MarkdownSummaryExtractor.extract(from: summary)
    var result: [String] = []
    if let decision = extracted.decisions.first {
      result.append("「\(excerpt(decision))」の判断理由と、見直すべき条件を整理して")
    } else { result.append("この記録で最も重要な結論と、その根拠は？") }
    if let question = extracted.openQuestions.first {
      result.append("「\(excerpt(question))」を決めるために、何を確認すればいい？")
    } else { result.append("この記録で、まだ確認が必要なことは？") }
    if let action = extracted.actions.first {
      result.append("「\(excerpt(action.title))」に着手するための準備と、依存関係を整理して")
    } else { result.append("この記録を踏まえて、次に取れる行動を提案して") }
    return result
  }

  private static func excerpt(_ text: String) -> String {
    let plain = text.replacingOccurrences(of: "**", with: "").split(separator: "／").first.map(String.init) ?? text
    return String(plain.prefix(36)) + (plain.count > 36 ? "…" : "")
  }
}
