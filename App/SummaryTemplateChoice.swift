import Foundation

/// Either a built-in or a marketplace template, so the picker and the generator
/// can treat them the same.
enum SummaryTemplateChoice: Hashable, Identifiable, Codable {
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

  var symbol: MemoraIcon {
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

  /// The base every automatic summary uses.
  static let standard = SummaryTemplateChoice.builtIn(.detailedOverview)

  static let adaptive = SummaryTemplateChoice.market(SummaryMarketTemplate(
    id: "content.adaptive", title: "内容に合わせる", detail: "資料にある内容に合わせて必要な見出しだけで整理",
    symbol: .sparkles, lead: "内容に合った要約", category: .learning,
    focus: "原文を読んで内容に必要な見出しだけを作る。根拠のない項目・記録なしの欄は作らない。会議で明示された約束だけをアクションにする。"))

  static var adaptiveSource: SummaryTemplateChoice {
    guard case .market(var template) = adaptive else { return adaptive }
    template.includesActions = false
    return .market(template)
  }

  /// The built-in templates offered when choosing one.
  static var builtInChoices: [SummaryTemplateChoice] {
    SummaryTemplate.allCases.map { .builtIn($0) }
  }
}
