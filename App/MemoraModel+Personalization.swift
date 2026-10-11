import Foundation

extension MemoraModel {
  var occupationSummary: String {
    let names = occupationProfile.orderedIDs.compactMap { OccupationCatalog.occupation($0)?.title }
    return names.isEmpty ? (occupationProfile.customOccupationName.isEmpty ? "未設定" : occupationProfile.customOccupationName)
      : names.joined(separator: "・")
  }

  var recommendedSummaryChoices: [SummaryTemplateChoice] {
    OccupationCatalog.recommendedIDs(for: occupationProfile).compactMap(summaryChoice)
  }

  var allSummaryChoices: [SummaryTemplateChoice] {
    SummaryTemplateChoice.builtInChoices + customTemplates.map { .market($0) }
      + SummaryTemplateCatalog.market.map { .market($0) }
  }

  func summaryChoice(_ id: String) -> SummaryTemplateChoice? {
    allSummaryChoices.first { $0.id == id }
  }

  func setOccupation(_ id: String, selected: Bool) {
    var profile = occupationProfile
    profile.select(id, isSelected: selected)
    occupationProfile = profile
  }
}
