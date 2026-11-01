import Foundation

/// A summary uses the choices resolved at admission. Later settings, template
/// edits or model removal cannot silently change the request already accepted.
struct SourceSummaryResolution: Equatable {
  var template: SummaryTemplateChoice
  var preferences: SummaryPreferences
  var engine: AIEngine
  var llm: LLMSelection
}
