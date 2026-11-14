import SwiftUI

struct ToolsSkillsList: View {
  @Environment(MemoraModel.self) private var model
  @Binding var query: String
  @State private var category: MemoraSkill.Category?

  var body: some View {
    let skills = model.skillCatalog.filter { ToolsCatalogSearch.matches(query, fields: $0.searchFields) }
    let groups = MemoraSkill.Category.allCases.filter { category == nil || category == $0 }.map { category in
      (category.title, skills.filter { $0.resolvedCategory == category })
    }
    let badges = Dictionary(uniqueKeysWithValues: Set(model.disabledSkillIDs).map { ("skill:" + $0, "無効") })
    MarketplaceCatalogColumn {
      Picker("用途", selection: $category) {
        Text("すべての用途").tag(Optional<MemoraSkill.Category>.none)
        ForEach(MemoraSkill.Category.allCases, id: \.self) { category in
          Text(category.title).tag(Optional(category))
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .accessibilityIdentifier("marketplace.skillCategory")
      ForEach(groups, id: \.0) { title, skills in
        if !skills.isEmpty {
          MarketplaceCardSection(title: title, items: skills.map(MarketplaceItem.skill), badges: badges)
        }
      }
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NavigationLink { SkillsView() } label: {
          Label("スキルを管理", icon: .sliderHorizontal3)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
      }
      if groups.allSatisfy({ $0.1.isEmpty }) {
        ToolsSearchEmptyState { query = "" }
      }
    }
  }
}
