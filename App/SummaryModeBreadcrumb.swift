import Foundation

/// What was decided about one record, and what the person chose instead.
///
/// The breadcrumb is the trace of one classification: the mode that was
/// read from the input, the template that was finally used, and whether
/// the person changed it. It carries no content, only the shape of the
/// decision.
struct SummaryModeBreadcrumb: Codable, Hashable, Sendable {
  /// The record this is about.
  var recordID: UUID
  /// The mode that was read from the input.
  var mode: SummaryMode
  /// The template that was used for the summary.
  var templateID: String
  /// When the decision was made.
  var decidedAt: Date
  /// The person chose a different template than the mode suggested.
  var wasCorrected: Bool
}

/// What the person has taught the app about each mode.
///
/// The counts are the templates the person actually chose for that mode.
/// They are a preference, not a rule: the app only follows one after the
/// person has made the same choice more than once.
struct SummaryModePreference: Codable, Equatable, Sendable {
  /// How many times the person chose a template for each mode.
  var templateCounts: [String: [String: Int]] = [:]

  /// The number of choices the person must make before the app follows one.
  static let minimumChoices = 2

  /// The template the person has chosen for a mode.
  ///
  /// It is nil when the person has not chosen often enough, or when two
  /// templates are equally likely, because a tie is not a preference.
  func preferredTemplateID(for mode: SummaryMode) -> String? {
    let counts = templateCounts[mode.rawValue] ?? [:]
    let ranked = counts.sorted { lhs, rhs in
      lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }
    guard let best = ranked.first, best.value >= Self.minimumChoices else { return nil }
    guard ranked.count == 1 || ranked[1].value < best.value else { return nil }
    return best.key
  }

  /// Records that the person used a template for a mode.
  mutating func record(mode: SummaryMode, templateID: String) {
    guard !templateID.isEmpty else { return }
    var counts = templateCounts[mode.rawValue] ?? [:]
    counts[templateID, default: 0] += 1
    templateCounts[mode.rawValue] = counts
  }
}
