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
