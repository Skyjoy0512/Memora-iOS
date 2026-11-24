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
  var sourceFingerprint: String?
  var knowledge: SummaryKnowledge?
  var modeBreadcrumb: SummaryModeBreadcrumb? = nil
  var reconciledUserEdits: Bool?

  static func snapshot(record: Meeting, templateID: String?, preferences: SummaryPreferences, modelInfo: String,
                       evidence: [GeneratedSummaryEvidence] = [], knowledge: SummaryKnowledge? = nil, reconciledUserEdits: Bool = false) -> Self {
    var sections = SummarySection.parse(record.summary)
    for index in sections.indices {
      let statements = sections[index].content.components(separatedBy: "\n").map {
        $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0
      }
      let matches = SummaryEvidence.matches(items: statements, transcript: record.transcript, duration: record.duration)
      sections[index].sourceReferences = record.transcript.filter { segment in
        matches.values.contains { $0.id == segment.id }
      }.map(\.id)
      let uniqueTitle = sections.filter { $0.title == sections[index].title }.count == 1
      let links = SummaryEvidence.validatedLinks(uniqueTitle ? evidence : [], sectionTitle: sections[index].title,
        recordID: record.id, transcript: record.transcript, duration: record.duration)
      sections[index].evidenceLinks = links.isEmpty ? nil : links
      var seen = Set(sections[index].sourceReferences)
      sections[index].sourceReferences += links.map(\.sourceSegmentID).filter { seen.insert($0).inserted }
    }
    return Self(sourceRecordID: record.id, templateID: templateID,
      summaryLength: preferences.length, displayOrder: preferences.displayOrder,
      sections: sections, modelInfo: modelInfo, schemaVersion: knowledge == nil ? 2 : 3,
      markdown: record.summary, keyPoints: record.keyPoints, decisions: record.decisions,
      openQuestions: record.openQuestions,
      sourceFingerprint: SummaryEvidence.fingerprint(record.transcript), knowledge: knowledge, reconciledUserEdits: reconciledUserEdits ? true : nil)
  }

  func matches(record: Meeting) -> Bool {
    sourceFingerprint != nil && reconciledUserEdits != true && sourceRecordID == record.id && markdown == record.summary && keyPoints == record.keyPoints &&
      decisions == record.decisions && openQuestions == record.openQuestions &&
      sourceFingerprint == SummaryEvidence.fingerprint(record.transcript)
  }

  static func displaySections(record: Meeting) -> [SummarySection] {
    var sections = snapshot(record: record, templateID: nil, preferences: SummaryPreferences(), modelInfo: "").sections
    guard let version = record.summaryVersions.first(where: { $0.id == record.activeSummaryVersionID }),
          version.sourceRecordID == record.id, version.markdown == record.summary else { return sections }
    for index in sections.indices {
      // Persisted section IDs bind links to this version; title-only joins could
      // attach one topic's evidence to another with the same visible heading.
      guard let saved = version.sections.first(where: { $0.order == sections[index].order && $0.content == sections[index].content && $0.title == sections[index].title }) else { continue }
      sections[index].id = saved.id
      let links = (saved.evidenceLinks ?? []).filter {
        $0.resolves(recordID: record.id, transcript: record.transcript, duration: record.duration)
      }
      var seen = Set(sections[index].sourceReferences)
      sections[index].sourceReferences += links.map(\.sourceSegmentID).filter { seen.insert($0).inserted }
    }
    return sections
  }

  private enum CodingKeys: String, CodingKey {
    case id, sourceRecordID, templateID, summaryLength, displayOrder, sections, generatedAt, modelInfo
    case schemaVersion, markdown, keyPoints, decisions, openQuestions, sourceFingerprint, knowledge, modeBreadcrumb, reconciledUserEdits
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    sourceRecordID = try values.decode(UUID.self, forKey: .sourceRecordID)
    templateID = try values.decodeIfPresent(String.self, forKey: .templateID)
    summaryLength = try values.decode(SummaryLength.self, forKey: .summaryLength)
    displayOrder = try values.decode(SummaryPreferences.DisplayOrder.self, forKey: .displayOrder)
    sections = try values.decode([SummarySection].self, forKey: .sections)
    generatedAt = try values.decode(Date.self, forKey: .generatedAt)
    modelInfo = try values.decode(String.self, forKey: .modelInfo)
    schemaVersion = (try? values.decode(Int.self, forKey: .schemaVersion)) ?? 1
    markdown = try values.decode(String.self, forKey: .markdown)
    keyPoints = try values.decode([String].self, forKey: .keyPoints)
    decisions = try values.decode([String].self, forKey: .decisions)
    openQuestions = try values.decode([String].self, forKey: .openQuestions)
    sourceFingerprint = try? values.decodeIfPresent(String.self, forKey: .sourceFingerprint)
    // Optional enrichment must never make a whole recording unrecoverable.
    knowledge = try? values.decodeIfPresent(SummaryKnowledge.self, forKey: .knowledge)
    modeBreadcrumb = try? values.decodeIfPresent(SummaryModeBreadcrumb.self, forKey: .modeBreadcrumb)
    reconciledUserEdits = try? values.decodeIfPresent(Bool.self, forKey: .reconciledUserEdits)
  }

  init(id: UUID = UUID(), sourceRecordID: UUID, templateID: String?, summaryLength: SummaryLength,
       displayOrder: SummaryPreferences.DisplayOrder, sections: [SummarySection], generatedAt: Date = .now,
       modelInfo: String, schemaVersion: Int = 1, markdown: String, keyPoints: [String], decisions: [String],
       openQuestions: [String], sourceFingerprint: String? = nil, knowledge: SummaryKnowledge? = nil, reconciledUserEdits: Bool? = nil) {
    self.id = id; self.sourceRecordID = sourceRecordID; self.templateID = templateID
    self.summaryLength = summaryLength; self.displayOrder = displayOrder; self.sections = sections
    self.generatedAt = generatedAt; self.modelInfo = modelInfo; self.schemaVersion = schemaVersion
    self.markdown = markdown; self.keyPoints = keyPoints; self.decisions = decisions; self.openQuestions = openQuestions
    self.sourceFingerprint = sourceFingerprint; self.knowledge = knowledge; self.reconciledUserEdits = reconciledUserEdits
  }
}
