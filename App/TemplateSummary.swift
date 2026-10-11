import Foundation

struct TemplateSummary: Identifiable, Hashable, Codable {
  var id: UUID = UUID()
  var sourceRecordID: UUID
  var templateID: String?
  var summaryLength: SummaryLength
  var displayOrder: SummaryPreferences.DisplayOrder
  var sections: [SummarySection]
  var generatedAt: Date = .now
  var modelInfo: String
  var schemaVersion = 1
  var markdown: String
  var keyPoints: [String]
  var decisions: [String]
  var openQuestions: [String]

  static func snapshot(
    record: Meeting, templateID: String?, preferences: SummaryPreferences, modelInfo: String
  ) -> Self {
    var sections = SummarySection.parse(record.summary)
    for index in sections.indices {
      let statements = sections[index].content.components(separatedBy: "\n").map {
        $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0
      }
      let matches = SummaryEvidence.matches(items: statements, transcript: record.transcript, duration: record.duration)
      sections[index].sourceReferences = record.transcript.filter { segment in
        matches.values.contains { $0.id == segment.id }
      }.map(\.id)
    }
    return Self(sourceRecordID: record.id, templateID: templateID,
         summaryLength: preferences.length, displayOrder: preferences.displayOrder,
         sections: sections, modelInfo: modelInfo,
         markdown: record.summary, keyPoints: record.keyPoints,
         decisions: record.decisions, openQuestions: record.openQuestions)
  }
}
