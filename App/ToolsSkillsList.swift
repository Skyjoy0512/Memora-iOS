import SwiftUI

struct ToolsSkillsList: View {
  @Environment(MemoraModel.self) private var model
  @Binding var query: String

  var body: some View {
    let groups: [(String, [MemoraSkill])] = [
      ("自分で作成", model.customSkills), ("Memora", MemoraSkill.bundled)
    ].map { title, skills in
      (title, skills.filter { ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.keywords) })
    }
    let badges = Dictionary(uniqueKeysWithValues: Set(model.disabledSkillIDs).map { ("skill:" + $0, "無効") })
    MarketplaceCatalogColumn {
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
