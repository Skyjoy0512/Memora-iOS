import Foundation

/// A finished summary: the document shown on the record, and the parts the app
/// files into their own places (lists, and tasks for the actions).
struct MeetingSummary {
  var markdown: String
  var keyPoints: [String] = []
  var decisions: [String] = []
  var openQuestions: [String] = []
  var actions: [SummaryActionItem] = []
  var templateID: String? = nil
  var knowledge: SummaryKnowledge? = nil
  var hasCompleteExtraction = true
  var evidence: [GeneratedSummaryEvidence] = []
}
