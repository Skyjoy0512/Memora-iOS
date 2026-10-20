import SwiftUI

struct ToolsTemplatesList: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    let custom = model.customTemplates
    let installed = SummaryTemplateCatalog.market.filter { model.installedTemplateIDs.contains($0.id) }
    let categories = SummaryTemplateCategory.allCases.compactMap { category -> (SummaryTemplateCategory, [SummaryMarketTemplate])? in
      let templates = SummaryTemplateCatalog.market.filter { $0.category == category }
      return templates.isEmpty ? nil : (category, templates)
    }
    List {
      if !custom.isEmpty || !installed.isEmpty {
        Section {
          ForEach(custom + installed) { template in ToolsTemplateRow(template: template) }
        } header: { ToolsSectionHeading(title: "マイテンプレート") }
      }
      ForEach(categories, id: \.0) { category, templates in
        Section {
          ForEach(templates) { template in ToolsTemplateRow(template: template) }
        } header: { ToolsSectionHeading(title: category.title) }
      }
      Section {
        NavigationLink { SummaryTemplateMarketplaceView() } label: {
          Label("テンプレートを検索・管理", icon: .magnifyingglass)
        }
      }
    }
  }
}

private struct ToolsTemplateRow: View {
  @Environment(MemoraModel.self) private var model
  var template: SummaryMarketTemplate

  var body: some View {
    NavigationLink { SummaryTemplateDetailView(templateID: template.id) } label: {
      ToolsCatalogRow(title: template.title,
        summary: template.detail.isEmpty ? template.sections.joined(separator: "・") : template.detail,
        badge: model.defaultSummaryChoice.id == template.id ? "自動生成の既定" : nil)
    }
    .listRowBackground(MemoraPalette.background)
  }
}
