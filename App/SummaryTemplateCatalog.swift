import Foundation

/// The templates available beyond the built-ins.
enum SummaryTemplateCatalog {
  static let market: [SummaryMarketTemplate] = [
    SummaryMarketTemplate(
      id: "market.retro",
      title: "振り返り（KPT）",
      detail: "続けたいこと・課題・次の試みで整理",
      symbol: .arrowTriangle2Circlepath,
      lead: "振り返り（続けたいこと・課題・次の試み）"
    ),
    SummaryMarketTemplate(
      id: "market.oneOnOne",
      title: "1on1",
      detail: "本人の状態と次の一歩に絞って整理",
      symbol: .person2,
      lead: "1on1（本人の状態と次の一歩）"
    ),
    SummaryMarketTemplate(
      id: "market.sales",
      title: "商談",
      detail: "顧客の要望と次の一手に絞って整理",
      symbol: .briefcase,
      lead: "商談（顧客の要望と次の一手）"
    ),
    SummaryMarketTemplate(
      id: "market.decisionLog",
      title: "決定ログ",
      detail: "決めたことと理由を中心に残す",
      symbol: .checkmarkSeal,
      lead: "決定ログ（決めたことと理由）"
    ),
    SummaryMarketTemplate(
      id: "market.standup",
      title: "デイリー",
      detail: "進捗と止まっている点を短く整理",
      symbol: .clock,
      lead: "デイリー（進捗と止まっている点）"
    )
  ]

  static func template(id: String) -> SummaryMarketTemplate? {
    market.first { $0.id == id }
  }
}
