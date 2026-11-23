import Foundation

extension MemoraModel {
  func automaticSummaryChoice(for meeting: Meeting, useCaseID: String?) -> SummaryTemplateChoice {
    if let useCase = OccupationCatalog.useCases.first(where: { $0.id == useCaseID }),
       let choice = useCase.templateIDs.compactMap(summaryChoice).first { return choice }
    if summaryPreferences.method == .fixed { return defaultSummaryChoice }
    return .adaptive
  }

  func automaticSummaryCandidates(for meeting: Meeting, fallback: SummaryTemplateChoice) -> [SummaryTemplateChoice] {
    let available = [SummaryTemplateChoice.adaptive] + allSummaryChoices
    if fallback.id == VideoSummaryTemplate.template.id { return [fallback] }
    let ids = SummaryTemplateSelector.candidateIDs(fallbackID: fallback.id,
      contentID: SummaryTemplateSelector.contentTemplateID(meeting.transcript.map(\.text).joined(separator: "\n")),
      recommendedIDs: recommendedSummaryChoices.map(\.id),
      genericIDs: [SummaryTemplateChoice.builtIn(.detailedOverview).id,
        SummaryTemplateChoice.builtIn(.meetingMinutes).id, "work.journal", SummaryTemplateChoice.builtIn(.actionPlan).id,
        "work.learning"],
      availableIDs: Set(available.map(\.id)))
    return ids.compactMap { id in available.first { $0.id == id } }
  }

  var occupationSummary: String {
    let names = occupationProfile.orderedIDs.compactMap { OccupationCatalog.occupation($0)?.title }
    return names.isEmpty ? (occupationProfile.customOccupationName.isEmpty ? "未設定" : occupationProfile.customOccupationName)
      : names.joined(separator: "・")
  }

  var recommendedSummaryChoices: [SummaryTemplateChoice] {
    OccupationCatalog.recommendedIDs(for: occupationProfile).compactMap(summaryChoice)
  }

  /// The templates a person can pick from: the built-in ones, the ones they
  /// wrote, and the catalog. The list only changes with the person's own
  /// templates, so it is kept until one of those changes.
  var allSummaryChoices: [SummaryTemplateChoice] {
    if let cachedSummaryChoices, cachedSummaryChoicesTemplates == customTemplates { return cachedSummaryChoices }
    let choices = SummaryTemplateChoice.builtInChoices + customTemplates.map { .market($0) }
      + SummaryTemplateCatalog.market.map { .market($0) }
    cachedSummaryChoicesTemplates = customTemplates
    cachedSummaryChoices = choices
    return choices
  }

  func summaryChoice(_ id: String) -> SummaryTemplateChoice? {
    if id == SummaryTemplateChoice.adaptive.id { return .adaptive }
    return allSummaryChoices.first { $0.id == id }
  }

  func setOccupation(_ id: String, selected: Bool) {
    guard OccupationCatalog.occupation(id) != nil,
          occupationProfile.selectedOccupationIDs.contains(id) != selected else { return }
    var profile = occupationProfile
    profile.select(id, isSelected: selected)
    occupationProfile = profile
    if followsOccupationSummaryTemplates { summaryPreferences.method = .automatic }
  }

  func setPrimaryOccupation(_ id: String?) {
    guard let id, occupationProfile.selectedOccupationIDs.contains(id),
          occupationProfile.primaryOccupationID != id else { return }
    occupationProfile.primaryOccupationID = id
    occupationProfile.updatedAt = .now
    if followsOccupationSummaryTemplates { summaryPreferences.method = .automatic }
  }
}
