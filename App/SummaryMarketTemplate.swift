import Foundation

/// A template beyond the built-ins: from the marketplace, or written by the
/// person. It says what to look for and how to write the summary — either as
/// sections, or, for the person's own, as a prompt in their own words.
struct SummaryMarketTemplate: Identifiable, Hashable, Codable {
  var id: String
  var title: String
  var detail: String
  var symbol: MemoraIcon
  /// How the template frames the summary, used as the AI instruction's lead.
  var lead: String
  var category: SummaryTemplateCategory = .meetings
  /// The `##` sections the summary is written under, in order.
  var sections: [String] = []
  /// What to pay attention to.
  var focus: String = ""
  /// The person's own instructions for how to write the summary. When set,
  /// it is followed instead of `sections`.
  var prompt: String = ""
  /// Whether the summary ends with an action table that becomes tasks.
  var includesActions = true
  /// True for a template the person wrote.
  var isCustom = false
  var occupationTags: [String] = []
  var useCaseTags: [String] = []
  var defaultDisplayOrder = 0
  var sensitivityClassification: SummarySensitivity = .general
  var supportedSummaryLengths: [SummaryLength] = SummaryLength.allCases

  var usesPrompt: Bool {
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var appendsMeetingQuestions: Bool {
    !isCustom && !id.hasPrefix("work.") && !id.hasPrefix("content.")
      && !sections.contains { $0.contains("未決") || $0.contains("持ち越") }
  }

  init(
    id: String,
    title: String,
    detail: String,
    symbol: MemoraIcon,
    lead: String,
    category: SummaryTemplateCategory = .meetings,
    sections: [String] = [],
    focus: String = "",
    prompt: String = "",
    includesActions: Bool = true,
    isCustom: Bool = false,
    occupationTags: [String] = [],
    useCaseTags: [String] = [],
    defaultDisplayOrder: Int = 0,
    sensitivityClassification: SummarySensitivity = .general,
    supportedSummaryLengths: [SummaryLength] = SummaryLength.allCases
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.symbol = symbol
    self.lead = lead
    self.category = category
    self.sections = sections
    self.focus = focus
    self.prompt = prompt
    self.includesActions = includesActions
    self.isCustom = isCustom
    self.occupationTags = occupationTags
    self.useCaseTags = useCaseTags
    self.defaultDisplayOrder = defaultDisplayOrder
    self.sensitivityClassification = sensitivityClassification
    self.supportedSummaryLengths = supportedSummaryLengths
  }

  /// Fields added in later builds are optional when reading, so templates
  /// saved by an older build still load.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
    symbol = (try? container.decode(MemoraIcon.self, forKey: .symbol)) ?? .docText
    lead = try container.decodeIfPresent(String.self, forKey: .lead) ?? title
    category = (try? container.decode(SummaryTemplateCategory.self, forKey: .category)) ?? .meetings
    sections = try container.decodeIfPresent([String].self, forKey: .sections) ?? []
    focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
    includesActions = try container.decodeIfPresent(Bool.self, forKey: .includesActions) ?? true
    isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    occupationTags = try container.decodeIfPresent([String].self, forKey: .occupationTags) ?? []
    useCaseTags = try container.decodeIfPresent([String].self, forKey: .useCaseTags) ?? []
    defaultDisplayOrder = try container.decodeIfPresent(Int.self, forKey: .defaultDisplayOrder) ?? 0
    sensitivityClassification = try container.decodeIfPresent(SummarySensitivity.self, forKey: .sensitivityClassification) ?? .general
    supportedSummaryLengths = try container.decodeIfPresent([SummaryLength].self, forKey: .supportedSummaryLengths) ?? SummaryLength.allCases
  }
}
