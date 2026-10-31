import Foundation

extension Meeting {
  var usesVideoSummary: Bool {
    if let version = summaryVersions.first(where: { $0.id == activeSummaryVersionID }),
       let templateID = version.templateID {
      return templateID == VideoSummaryTemplate.template.id
    }
    return summaryUseCaseID == VideoSummaryTemplate.useCase.id
  }
}
