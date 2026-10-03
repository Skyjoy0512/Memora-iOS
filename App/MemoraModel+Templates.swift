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

  /// What 自動生成 writes with: the chosen default while it is still
  /// available, otherwise the built-in 詳細な概要.
  var defaultSummaryChoice: SummaryTemplateChoice {
    guard let id = defaultTemplateID,
          let template = installedMarketTemplates.first(where: { $0.id == id }) else {
      return .standard
    }
    return .market(template)
  }

  private func persistInstalledTemplates() {
    UserDefaults.standard.set(installedTemplateIDs, forKey: StorageKey.installedTemplates)
  }
}
