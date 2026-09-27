import Foundation

/// A template that is not built in: it can be added from the marketplace and
/// then shapes how a summary is written.
struct SummaryMarketTemplate: Identifiable, Hashable {
  var id: String
  var title: String
  var detail: String
  var symbol: MemoraIcon
  /// How the template frames the summary, used as the AI instruction's lead.
  var lead: String
}
