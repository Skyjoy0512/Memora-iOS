import Foundation

/// One global extraction is shared by every section, including later reversals.
struct SummaryCompositionPlan: Codable {
  static let maximumBytes = 256 * 1024
  var schemaVersion: Int
  var overview: String
  var sections: [Section]
  var extraction: Extraction

  func isValid(input: MeetingSummaryInput, source: SummarySourceIndex, compact: Bool) -> Bool {
    guard schemaVersion == 1, sections.count <= 8, (!sections.isEmpty || !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
          Set(sections.map(\.id)).count == sections.count, Set(sections.map(\.title)).count == sections.count,
          extraction.knowledge.schemaVersion == 1, extraction.knowledge.facts.count <= 256,
          extraction.knowledge.topics.count <= 64 else { return false }
    let allowed = Set(([input.template] + input.automaticCandidates).map(\.id))
    guard extraction.templateID.map({ allowed.contains($0) }) ?? true,
          Set(extraction.knowledge.selectedProfileIDs).isSubset(of: allowed),
          Set(extraction.knowledge.facts.map(\.id)).count == extraction.knowledge.facts.count else { return false }
    let topicIDs = Set(extraction.knowledge.topics.map(\.id))
    guard topicIDs.count == extraction.knowledge.topics.count,
          extraction.knowledge.topics.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
          sections.allSatisfy({ section in
      !section.id.isEmpty && topicIDs.contains(section.id) && !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        section.title.count <= 120 && !section.title.contains(where: \.isNewline) &&
        !section.sourceSegmentIDs.isEmpty && section.sourceSegmentIDs.count <= 512 &&
        section.sourceSegmentIDs.allSatisfy { source.originalID(for: $0, allowShortIDs: compact) != nil }
    }) else { return false }
    let factIDs = Set(extraction.knowledge.facts.map(\.id))
    for fact in extraction.knowledge.facts {
      guard !fact.id.isEmpty, fact.id.count <= 80, !fact.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fact.content.count <= 4_000, fact.relatedTopicID.map({ topicIDs.contains($0) }) ?? true,
            Set(fact.relatedFactIDs ?? []).isSubset(of: factIDs),
            (fact.sourceReferences ?? []).allSatisfy({ source.validates(id: $0.sourceSegmentID, quote: $0.quote, allowShortIDs: compact) }) else { return false }
      if fact.status.isVisible {
        guard let references = fact.sourceReferences, !references.isEmpty, references.count <= 64,
              references.allSatisfy({ source.validates(id: $0.sourceSegmentID, quote: $0.quote, allowShortIDs: compact) }) else { return false }
      }
    }
    let confirmed = extraction.knowledge.facts.filter { $0.status == .confirmed }
    guard (extraction.decisions ?? []).allSatisfy({ text in confirmed.contains { $0.category == .decision && $0.content == text } }) else { return false }
    for action in extraction.actions ?? [] {
      guard let fact = confirmed.first(where: { $0.category == .action && $0.content == action.title }) else { return false }
      let references = fact.sourceReferences ?? []
      for value in [action.owner, action.due].compactMap({ $0 }) {
        guard references.contains(where: { reference in
          reference.quote.contains(value) || (action.owner == value && source.entries.contains {
            source.originalID(for: reference.sourceSegmentID, allowShortIDs: compact) == $0.segment.id &&
              $0.segment.speakerIsCertain && $0.segment.speaker == value
          })
        }) else { return false }
      }
    }
    return true
  }

  static func decode(_ text: String) -> Self? {
    guard text.utf8.count <= maximumBytes else { return nil }
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("```json\n"), value.hasSuffix("\n```") { value = String(value.dropFirst(8).dropLast(4)) }
    let data = Data(value.utf8)
    // Stored enrichment deliberately recovers damaged facts. A new global plan
    // must instead reject them before a dropped reversal can reach a section.
    guard let strict = try? JSONDecoder().decode(StrictShape.self, from: data),
          strict.extraction.knowledge.schemaVersion == 1, strict.extraction.knowledge.selectedProfileIDs.count <= 3,
          strict.extraction.knowledge.topics.count <= 64, strict.extraction.knowledge.facts.count <= 256,
          strict.extraction.knowledge.coverage.count <= 64 else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  struct Section: Codable {
    var id: String
    var title: String
    var sourceSegmentIDs: [String]
  }

  struct Extraction: Codable {
    var templateID: String?
    var knowledge: SummaryKnowledge
    var keyPoints: [String]?
    var decisions: [String]?
    var openQuestions: [String]?
    var actions: [SummaryActionItem]?
    var sourceReferences: [GeneratedSummaryEvidence]?
  }

  private struct StrictShape: Decodable {
    var extraction: Fields
    struct Fields: Decodable { var knowledge: Knowledge }
    struct Knowledge: Decodable {
      var schemaVersion: Int
      var selectedProfileIDs: [String]
      var contentType: SummaryKnowledge.ContentType
      var topics: [SummaryKnowledge.Topic]
      var facts: [SummaryKnowledge.Fact]
      var coverage: [SummaryKnowledge.Coverage]
    }
  }
}
