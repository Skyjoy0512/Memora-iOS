import Foundation

/// A finite local plan; extra searches depend on actual coverage, never on web-page instructions.
struct ResearchPlan {
  static let maximumSearches = 6
  static let maximumSources = 16
  static let maximumSeconds: TimeInterval = 120
  static let maximumModelCalls = 1
  static let maximumOutputTokens = 4_096
  static let maximumContextCharacters = 8_000
  static let costNotice = "検索最大6回・取得ソース16件・比較AI1回・120秒。ローカルの回数上限で、請求額上限ではありません。料金は契約とモデルによって異なり、未確定です。"

  static func gaps(in sources: [WebResearchSource]) -> [String] {
    var gaps: [String] = []
    if sources.count < 6 { gaps.append("取得ソースが少ない") }
    if Set(sources.compactMap { $0.url.host }).count < 3 { gaps.append("発行元の種類が少ない") }
    if !sources.contains(where: { isPrimaryCandidate($0.url) }) { gaps.append("一次資料の候補が未確認") }
    if sources.contains(where: { $0.publishedAt == nil }) { gaps.append("公開・更新日時が未確認の資料がある") }
    return gaps
  }

  static func isPrimaryCandidate(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return [".go.jp", ".gov", ".ac.jp", ".edu"].contains { host.hasSuffix($0) }
      || host.hasPrefix("docs.") || host.hasPrefix("developer.")
  }

  static func nextQuery(topic: String, attempted: [String], sources: [WebResearchSource]) -> String? {
    guard attempted.count < maximumSearches, !gaps(in: sources).isEmpty else { return nil }
    let base = String(topic.prefix(480))
    let suffixes = [" 公式 一次資料 統計", " 最新 発表 更新日", " 課題 制約 異なる見解"]
    return suffixes.map { base + $0 }.first { !attempted.contains($0) }
  }

  static func hasInvalidCitations(_ text: String, sourceCount: Int) -> Bool {
    let regex = try! NSRegularExpression(pattern: "【Web([0-9]+)】")
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains { match in
      guard let range = Range(match.range(at: 1), in: text), let n = Int(text[range]) else { return true }
      return n < 1 || n > sourceCount
    }
  }
}
