import Foundation

/// One subject a meeting moved through, with what was said about it. The
/// on-device path builds these section by section and lays them out in Swift.
struct SummaryTopic: Hashable {
  var title: String
  var startTime: TimeInterval
  var endTime: TimeInterval
  var speakers: [String] = []
  var points: [String] = []
  var decisions: [String] = []
  var concerns: [String] = []
  var actions: [SummaryActionItem] = []
  var questions: [String] = []
  var facts: [SummaryKnowledge.Fact] = []
  var evidence: [GeneratedSummaryEvidence] = []
  var relations: [SummaryRelation] = []
}
