import Foundation

/// A template that is not built in: it can be added from the marketplace and
/// then shapes how a summary is written.
struct SummaryMarketTemplate: Identifiable, Hashable {
  var id: String
  var title: String
  var detail: String
  var symbol: String
  /// How the template frames the summary, used as the AI instruction's lead.
  var lead: String
}

/// The templates available beyond the built-ins.
enum SummaryTemplateCatalog {
  static let market: [SummaryMarketTemplate] = [
    SummaryMarketTemplate(
      id: "market.retro",
      title: "振り返り（KPT）",
      detail: "続けたいこと・課題・次の試みで整理",
      symbol: "arrow.triangle.2.circlepath",
      lead: "振り返り（続けたいこと・課題・次の試み）"
    ),
    SummaryMarketTemplate(
      id: "market.oneOnOne",
      title: "1on1",
      detail: "本人の状態と次の一歩に絞って整理",
      symbol: "person.2",
      lead: "1on1（本人の状態と次の一歩）"
    ),
    SummaryMarketTemplate(
      id: "market.sales",
      title: "商談",
      detail: "顧客の要望と次の一手に絞って整理",
      symbol: "briefcase",
      lead: "商談（顧客の要望と次の一手）"
    ),
    SummaryMarketTemplate(
      id: "market.decisionLog",
      title: "決定ログ",
      detail: "決めたことと理由を中心に残す",
      symbol: "checkmark.seal",
      lead: "決定ログ（決めたことと理由）"
    ),
    SummaryMarketTemplate(
      id: "market.standup",
      title: "デイリー",
      detail: "進捗と止まっている点を短く整理",
      symbol: "clock",
      lead: "デイリー（進捗と止まっている点）"
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

  /// The instruction handed to the AI engine when a record is re-summarized.
  var summaryInstruction: String {
    switch self {
    case .builtIn(let template):
      switch template {
      case .automatic:
        "次の文字起こしを、内容に合う形で日本語で簡潔に要約してください。記録に無いことは書かないでください。"
      case .meetingMinutes:
        "次の文字起こしから、議事録として要点・決まったこと・未決事項を日本語で簡潔にまとめてください。記録に無いことは書かないでください。"
      case .detailedMinutes:
        "次の文字起こしから、話題の流れと背景が分かる詳細な議事録を日本語で作ってください。記録に無いことは書かないでください。"
      case .actionPlan:
        "次の文字起こしから、担当と次にすることを中心に日本語でまとめてください。記録に無いことは書かないでください。"
      }
    case .market(let template):
      "次の文字起こしを、\(template.lead)の観点で日本語で簡潔にまとめてください。記録に無いことは書かないでください。"
    }
  }

  /// The built-in templates offered when choosing one, automatic excluded.
  static var builtInChoices: [SummaryTemplateChoice] {
    SummaryTemplate.allCases.filter { $0 != .automatic }.map { .builtIn($0) }
  }
}
