import Foundation

extension MemoraModel {
  /// Templates offered when choosing one: the person's own first, then those
  /// added from the marketplace, in catalog order.
  var installedMarketTemplates: [SummaryMarketTemplate] {
    customTemplates + SummaryTemplateCatalog.market.filter { installedTemplateIDs.contains($0.id) }
  }

  func installTemplate(_ id: String) {
    guard !installedTemplateIDs.contains(id) else { return }
    installedTemplateIDs.append(id)
    persistInstalledTemplates()
  }

  func uninstallTemplate(_ id: String) {
    installedTemplateIDs.removeAll { $0 == id }
    persistInstalledTemplates()
    if defaultTemplateID == id { defaultTemplateID = nil }
  }

  func isTemplateAvailable(_ id: String) -> Bool {
    installedTemplateIDs.contains(id) || customTemplates.contains { $0.id == id }
  }

  // MARK: - The person's own templates

  /// Adds or updates one of the person's templates.
  func saveCustomTemplate(_ template: SummaryMarketTemplate) {
    var template = template
    template.isCustom = true
    template.lead = template.title
    if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
      customTemplates[index] = template
    } else {
      customTemplates.append(template)
    }
    persistInBackground(customTemplates, forKey: StorageKey.customTemplates)
  }

  func deleteCustomTemplate(_ id: String) {
    customTemplates.removeAll { $0.id == id }
    persistInBackground(customTemplates, forKey: StorageKey.customTemplates)
    if defaultTemplateID == id { defaultTemplateID = nil }
  }

  // MARK: - Default

  var defaultSummaryChoice: SummaryTemplateChoice {
    let id = SummaryTemplateSelector.preferredTemplateID(explicitID: defaultTemplateID,
      recommendedIDs: OccupationCatalog.recommendedIDs(for: occupationProfile),
      availableIDs: Set(allSummaryChoices.map(\.id)), fallbackID: SummaryTemplateChoice.standard.id)
    return summaryChoice(id) ?? .standard
  }

  var followsOccupationSummaryTemplates: Bool { defaultTemplateID == nil }

  func useOccupationSummaryTemplates() {
    defaultTemplateID = nil
    summaryPreferences.method = .automatic
  }

  func setDefaultSummaryTemplate(_ id: String) {
    guard summaryChoice(id) != nil else { return }
    defaultTemplateID = id
    summaryPreferences.method = .fixed
  }

  private func persistInstalledTemplates() {
    UserDefaults.standard.set(installedTemplateIDs, forKey: StorageKey.installedTemplates)
  }
}
