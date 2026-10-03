import Foundation

/// A template beyond the built-ins: from the marketplace, or written by the
/// person. It says what to look for and which sections to write.
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
  /// What to pay attention to, in the person's words for their own templates.
  var focus: String = ""
  /// Whether the summary ends with an action table that becomes tasks.
  var includesActions = true
  /// True for a template the person wrote.
  var isCustom = false
}
