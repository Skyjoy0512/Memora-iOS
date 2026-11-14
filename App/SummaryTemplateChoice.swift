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


extension SummaryTemplateChoice {
  /// Existing custom instructions remain an explicit output contract. Catalog
  /// sections are extraction lenses, never mandatory document headings.
  var preservesFormat: Bool {
    if case .market(let template) = self { return template.isCustom || template.usesPrompt }
    return false
  }

  var extractionProfile: ExtractionProfile {
    if case .market(let template) = self {
      return ExtractionProfile(profileID: id, purpose: template.lead,
        extractionFocus: template.sections, importantFacts: template.detail,
        suggestedSections: template.sections, presentationPreferences:
          template.category == .life ? "出来事と本人の気づきを自然な文章で整理。業務文書化しない。" :
          template.category == .learning ? "概念・説明・具体例を整理。会議の決定や宿題を強制しない。" :
          "背景と理由は文章、条件は箇条書き、比較や数値は必要な場合だけ表。",
        domainSpecificRules: template.focus,
        actionExtractionPolicy: template.includesActions ? "実際に約束された行動だけ。提案や一般的な勧めはタスクにしない。" : "actionsは空配列。自動タスク抽出は禁止。")
    }
    let focus: [String]
    let presentation: String
    switch self {
    case .builtIn(.detailedOverview):
      focus = ["背景・目的", "主要トピック", "判断理由", "条件・反対意見", "実際の行動"]
      presentation = "理解に必要な経緯を保持し、話題の内容がわかる見出しで整理。話題ごとの同じ小見出しの反復を避ける。"
    case .builtIn(.meetingMinutes):
      focus = ["議論", "合意と保留", "判断理由", "次の行動"]
      presentation = "論点と結論を簡潔に関連付ける。"
    case .builtIn(.detailedMinutes):
      focus = ["議論の時系列", "当初案と最終判断", "変更理由", "条件と未解決事項"]
      presentation = "話題は時間順に整理。原文にある時刻だけを使う。"
    default:
      focus = ["合意した行動", "明示された担当・期限", "前提と依存関係"]
      presentation = "実際のアクションを優先。行動がなければ会話にある重要な情報だけを残す。"
    }
    return ExtractionProfile(profileID: id, purpose: title, extractionFocus: focus,
      importantFacts: detail, suggestedSections: [], presentationPreferences: presentation,
      domainSpecificRules: "提案を決定にせず、理由を推測しない。", actionExtractionPolicy: "実際に約束された行動だけ抽出する。")
  }

  struct ExtractionProfile {
    var profileID: String
    var purpose: String
    var extractionFocus: [String]
    var importantFacts: String
    var suggestedSections: [String]
    var presentationPreferences: String
    var domainSpecificRules: String
    var actionExtractionPolicy: String

    var instruction: String {
      "ID: \(profileID) | 目的: \(purpose) | 抽出観点: \(extractionFocus.joined(separator: " / ")) | 重要情報: \(importantFacts) | 用途の規則: \(domainSpecificRules) | 表現: \(presentationPreferences) | 行動: \(actionExtractionPolicy)"
    }
  }
}
