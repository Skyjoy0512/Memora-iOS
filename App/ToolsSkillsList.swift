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
    List {
      ForEach(groups, id: \.0) { title, skills in
        if !skills.isEmpty {
          Section {
            ForEach(skills) { skill in
              NavigationLink { SkillDetailView(skillID: skill.id) } label: {
                ToolsCatalogRow(title: skill.name, summary: skill.summary,
                  badge: model.disabledSkillIDs.contains(skill.id) ? "無効" : nil)
              }
              .listRowBackground(MemoraPalette.background)
            }
          } header: { ToolsSectionHeading(title: title) }
        }
      }
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Section {
          NavigationLink { SkillsView() } label: {
            SettingsLabel("スキルを管理", icon: .sliderHorizontal3)
          }
          .listRowBackground(MemoraPalette.background)
        } footer: {
          Text("繰り返す作業の手順を保存し、@や「チャットで使用」で呼び出せます。依頼に名前やキーワードが含まれると自動選択します。右上の＋から作成できます。")
        }
      }
    }
    .overlay(alignment: .top) {
      if groups.allSatisfy({ $0.1.isEmpty }) {
        ToolsSearchEmptyState { query = "" }
      }
    }
  }
}
