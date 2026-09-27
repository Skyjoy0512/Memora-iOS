import Foundation

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

  /// The built-in templates offered when choosing one.
  static var builtInChoices: [SummaryTemplateChoice] {
    SummaryTemplate.allCases.map { .builtIn($0) }
  }
}
