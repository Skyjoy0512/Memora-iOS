import SwiftUI

struct ToolsSkillsList: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    let groups: [(String, [MemoraSkill])] = [
      ("自分で作成", model.customSkills), ("Memora", MemoraSkill.bundled)
    ]
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
      Section {
        NavigationLink { SkillsView() } label: {
          SettingsLabel("スキルを管理", icon: .sliderHorizontal3)
        }
        .listRowBackground(MemoraPalette.background)
      } footer: {
        Text("依頼に合う手順をAsk AIが選びます。右上の＋から自分のスキルを作成できます。")
      }
    }
  }
}
