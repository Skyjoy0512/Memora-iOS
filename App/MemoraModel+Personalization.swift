import Foundation

extension MemoraModel {
  func automaticSummaryChoice(for meeting: Meeting, useCaseID: String?) -> SummaryTemplateChoice {
    if let useCase = OccupationCatalog.useCases.first(where: { $0.id == useCaseID }),
       let choice = useCase.templateIDs.compactMap(summaryChoice).first { return choice }
    if summaryPreferences.method == .fixed { return defaultSummaryChoice }
    if let id = SummaryTemplateSelector.contentTemplateID(meeting.transcript.map(\.text).joined(separator: "\n")),
       let choice = summaryChoice(id) { return choice }
    return defaultSummaryChoice
  }

  func automaticSummaryCandidates(for meeting: Meeting, fallback: SummaryTemplateChoice) -> [SummaryTemplateChoice] {
    let available = allSummaryChoices
    let ids = SummaryTemplateSelector.candidateIDs(fallbackID: fallback.id,
      contentID: SummaryTemplateSelector.contentTemplateID(meeting.transcript.map(\.text).joined(separator: "\n")),
      recommendedIDs: recommendedSummaryChoices.map(\.id),
      genericIDs: [SummaryTemplateChoice.builtIn(.detailedOverview).id,
        SummaryTemplateChoice.builtIn(.meetingMinutes).id, "work.journal", SummaryTemplateChoice.builtIn(.actionPlan).id],
      availableIDs: Set(available.map(\.id)))
    return ids.compactMap { id in available.first { $0.id == id } }
  }

  func restoreSummary(_ versionID: UUID, meetingID: UUID) {
    guard let record = meeting(id: meetingID), !processing.isActive(meetingID),
          let version = record.summaryVersions.first(where: { $0.id == versionID }) else { return }
    updateMeeting(meetingID) { meeting in
      if !meeting.summary.isEmpty, !meeting.summaryVersions.contains(where: { $0.markdown == meeting.summary }) {
        meeting.summaryVersions.append(.snapshot(record: meeting, templateID: nil,
          preferences: summaryPreferences, modelInfo: "手動編集・旧形式"))
      }
      meeting.summary = version.markdown
      meeting.keyPoints = version.keyPoints
      meeting.decisions = version.decisions
      meeting.openQuestions = version.openQuestions
      meeting.activeSummaryVersionID = version.id
      meeting.status = .ready
    }
    announce("要約を復元しました。タスク・原音声・文字起こしは変更していません。")
  }
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
