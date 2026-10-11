import Foundation

extension Meeting {
  var minimumPrivacyClassification: RecordPrivacy.Classification {
    var copy = self
    copy.privacy = RecordPrivacy()
    return copy.effectivePrivacy.classification
  }

  var effectivePrivacy: RecordPrivacy {
    var result = privacy
    let ids = summaryVersions.compactMap(\.templateID)
      + (OccupationCatalog.useCases.first(where: { $0.id == summaryUseCaseID })?.templateIDs ?? [])
    for id in ids {
      if let template = SummaryTemplateCatalog.template(id: id) { result.protect(template.sensitivityClassification) }
    }
    result.updatedAt = privacy.updatedAt
    return result
  }
}
