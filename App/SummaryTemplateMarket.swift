import Foundation

/// A template that is not built in: it can be added from the marketplace and
/// then shapes how a summary is written.
struct SummaryMarketTemplate: Identifiable, Hashable {
  var id: String
  var title: String
  var detail: String
  var symbol: String
  /// How the template frames the summary. The transcript is placed under it.
  var lead: String

  func summary(from transcript: [TranscriptSegment]) -> String {
    let excerpt = transcript
      .prefix(2)
      .map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !excerpt.isEmpty else { return lead }

    let trimmed = excerpt.count > 90 ? excerpt.prefix(90) + "…" : excerpt
    return "\(lead)\n\n\(trimmed)"
  }
}

/// The templates available beyond the built-ins.
enum SummaryTemplateCatalog {
  static let market: [SummaryMarketTemplate] = [
    SummaryMarketTemplate(
      id: "market.retro",
      title: "振り返り（KPT）",
      detail: "続けたいこと・課題・次の試みで整理",
      symbol: "arrow.triangle.2.circlepath",
      lead: "振り返りとして、続けたいこと・課題・次の試みの観点で整理しました。"
    ),
    SummaryMarketTemplate(
      id: "market.oneOnOne",
      title: "1on1",
      detail: "本人の状態と次の一歩に絞って整理",
      symbol: "person.2",
      lead: "1on1として、本人の状態と次にすることに絞って整理しました。"
    ),
    SummaryMarketTemplate(
      id: "market.sales",
      title: "商談",
      detail: "顧客の要望と次の一手に絞って整理",
      symbol: "briefcase",
      lead: "商談として、顧客の要望と次の一手に絞って整理しました。"
    ),
    SummaryMarketTemplate(
      id: "market.decisionLog",
      title: "決定ログ",
      detail: "決めたことと理由を中心に残す",
      symbol: "checkmark.seal",
      lead: "決定ログとして、決めたこととその理由を中心に残しました。"
    ),
    SummaryMarketTemplate(
      id: "market.standup",
      title: "デイリー",
      detail: "進捗と止まっている点を短く整理",
      symbol: "clock",
      lead: "デイリーとして、進捗と止まっている点を短く整理しました。"
    )
  ]

  static func template(id: String) -> SummaryMarketTemplate? {
    market.first { $0.id == id }
  }
}

/// Either a built-in or a marketplace template, so the picker and the generator
/// can treat them the same.
enum SummaryTemplateChoice: Hashable, Identifiable {
  case builtIn(SummaryTemplate)
  case market(SummaryMarketTemplate)

  var id: String {
    switch self {
    case .builtIn(let template): "builtin.\(template.rawValue)"
    case .market(let template): template.id
    }
  }

  var title: String {
    switch self {
    case .builtIn(let template): template.title
    case .market(let template): template.title
    }
  }

  var detail: String {
    switch self {
    case .builtIn(let template): template.detail
    case .market(let template): template.detail
    }
  }

  var symbol: String {
    switch self {
    case .builtIn(let template): template.symbol
    case .market(let template): template.symbol
    }
  }

  var processingLabel: String {
    switch self {
    case .builtIn(let template): template.processingLabel
    case .market(let template): "\(template.title)として整理中"
    }
  }

  /// The built-in templates offered when choosing one, automatic excluded.
  static var builtInChoices: [SummaryTemplateChoice] {
    SummaryTemplate.allCases.filter { $0 != .automatic }.map { .builtIn($0) }
  }
}
