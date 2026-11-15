import Foundation

extension Meeting {
  var activeSummaryVersion: TemplateSummary? {
    summaryVersions.first { $0.id == activeSummaryVersionID && $0.sourceRecordID == id }
  }

  var currentSummaryKnowledge: SummaryKnowledge? {
    guard let version = activeSummaryVersion, version.knowledge != nil, version.matches(record: self) else { return nil }
    return version.knowledge
  }

  /// Recheck the current source at the consumption boundary. Stored enrichment
  /// is recoverable and may predate a stricter validator; a source fingerprint
  /// alone must not promote a missing quote or a forged identity into context.
  var reusableSummaryFacts: [SummaryKnowledge.Fact] {
    guard let knowledge = currentSummaryKnowledge, knowledge.schemaVersion == 1 else { return [] }
    let segments = Dictionary(grouping: transcript, by: \.id)
    var seen: Set<String> = []
    return knowledge.facts.filter { fact in
      guard fact.status.isVisible, !fact.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fact.content.count <= 4_000, let references = fact.sourceReferences, !references.isEmpty,
            references.count <= 8 else { return false }
      var speakers: Set<String> = []
      for reference in references {
        guard let id = UUID(uuidString: reference.sourceSegmentID), let matches = segments[id], matches.count == 1,
              (8...2_000).contains(reference.quote.count), matches[0].text.contains(reference.quote) else { return false }
        if let speaker = matches[0].speakerID { speakers.insert(speaker) }
      }
      guard Set(fact.speakerIDs ?? []).isSubset(of: speakers) else { return false }
      return seen.insert(fact.category.rawValue + ":" + fact.status.rawValue + ":" + fact.content).inserted
    }
  }

  var summaryKnowledgeText: String {
    reusableSummaryFacts.map { fact in
      let ids = (fact.sourceReferences ?? []).map(\.sourceSegmentID).joined(separator: ",")
      return fact.status.label + ": " + fact.content + " [sourceSegmentID=" + ids + "]"
    }.joined(separator: "\n")
  }

  var usesVideoSummary: Bool {
    if let version = summaryVersions.first(where: { $0.id == activeSummaryVersionID }),
       let templateID = version.templateID {
      return templateID == VideoSummaryTemplate.template.id
    }
    return summaryUseCaseID == VideoSummaryTemplate.useCase.id
  }
}
