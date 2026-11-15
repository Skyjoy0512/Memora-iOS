import Foundation

/// The evaluation store retains the full generated result, never an app record.
struct NativeSummarySnapshot: Encodable {
  var markdown: String
  var keyPoints: [String]
  var decisions: [String]
  var openQuestions: [String]
  var actions: [SummaryActionItem]
  var templateID: String?
  var knowledge: SummaryKnowledge?
  var hasCompleteExtraction: Bool
  var evidence: [GeneratedSummaryEvidence]

  init(_ summary: MeetingSummary) {
    markdown = summary.markdown
    keyPoints = summary.keyPoints
    decisions = summary.decisions
    openQuestions = summary.openQuestions
    actions = summary.actions
    templateID = summary.templateID
    knowledge = summary.knowledge
    hasCompleteExtraction = summary.hasCompleteExtraction
    evidence = summary.evidence
  }
}
