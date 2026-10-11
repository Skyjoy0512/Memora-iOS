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
    record: Meeting, templateID: String?, preferences: SummaryPreferences, modelInfo: String,
    evidence: [GeneratedSummaryEvidence] = []
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
      let links = SummaryEvidence.validatedLinks(evidence, sectionTitle: sections[index].title,
        recordID: record.id, transcript: record.transcript, duration: record.duration)
      sections[index].evidenceLinks = links.isEmpty ? nil : links
      var seen = Set(sections[index].sourceReferences)
      sections[index].sourceReferences += links.map(\.sourceSegmentID).filter { seen.insert($0).inserted }
    }
    return Self(sourceRecordID: record.id, templateID: templateID,
         summaryLength: preferences.length, displayOrder: preferences.displayOrder,
         sections: sections, modelInfo: modelInfo,
         schemaVersion: sections.contains { !($0.evidenceLinks ?? []).isEmpty } ? 2 : 1,
         markdown: record.summary, keyPoints: record.keyPoints,
         decisions: record.decisions, openQuestions: record.openQuestions)
  }

  static func displaySections(record: Meeting) -> [SummarySection] {
    var sections = snapshot(record: record, templateID: nil, preferences: SummaryPreferences(), modelInfo: "").sections
    guard let version = record.summaryVersions.first(where: { $0.id == record.activeSummaryVersionID }),
          version.sourceRecordID == record.id, version.markdown == record.summary else { return sections }
    for index in sections.indices {
      let links = version.sections.filter { $0.title == sections[index].title }.flatMap { $0.evidenceLinks ?? [] }
        .filter { $0.resolves(recordID: record.id, transcript: record.transcript, duration: record.duration) }
      var seen = Set(sections[index].sourceReferences)
      sections[index].sourceReferences += links.map(\.sourceSegmentID).filter { seen.insert($0).inserted }
    }
    return sections
  }
}
