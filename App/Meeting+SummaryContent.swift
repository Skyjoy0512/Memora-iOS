import Foundation

extension Meeting {
  var activeSummaryVersion: TemplateSummary? {
    summaryVersions.first { $0.id == activeSummaryVersionID && $0.sourceRecordID == id }
  }

  var currentSummaryKnowledge: SummaryKnowledge? {
    guard let version = activeSummaryVersion, version.knowledge != nil, version.matches(record: self) else { return nil }
    return version.knowledge
  }

  var usesVideoSummary: Bool {
    if let version = summaryVersions.first(where: { $0.id == activeSummaryVersionID }),
       let templateID = version.templateID {
      return templateID == VideoSummaryTemplate.template.id
    }
    return summaryUseCaseID == VideoSummaryTemplate.useCase.id
  }
}
