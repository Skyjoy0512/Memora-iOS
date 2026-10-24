import Foundation

/// A summary the person started that may still need to finish after the app
/// leaves the foreground. The parameters are the ones chosen in the summary
/// sheet, so a background run writes the same document the foreground would.
struct PendingSummaryJob: Codable, Identifiable, Sendable {
  var id = UUID()
  var meetingID: UUID
  var choice: SummaryTemplateChoice
  var engineRawValue: String
  var llm: LLMSelection
  var automaticallySelect: Bool
  var useCaseID: String?
  var preferences: SummaryPreferences
  var cloudDisclosureConfirmed: Bool
  var usesCloud: Bool
  var createdAt = Date.now
  /// Older jobs have no fingerprint and must be confirmed again, not silently
  /// reuse a one-time disclosure against possibly changed record contents.
  var inputFingerprint: String? = nil
  var requiresUserRetry: Bool? = nil

  var engine: AIEngine {
    AIEngine(rawValue: engineRawValue) ?? .automatic
  }
}
