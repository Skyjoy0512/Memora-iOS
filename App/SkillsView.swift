import SwiftUI

struct SkillsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""

  var body: some View {
    let skills = MemoraSkill.bundled.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    List {
      Section {
        ForEach(skills) { skill in
          Toggle(isOn: Binding(
            get: { !model.disabledSkillIDs.contains(skill.id) },
            set: { model.setSkillEnabled(skill.id, enabled: $0) })) {
              VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                Text(skill.summary).font(.caption).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
        }
      } footer: {
        Text("依頼に合う補助手順を自動選択します。スキルは外部サービスへの接続や権限を追加しません。")
      }
    }
    .searchable(text: $query, prompt: "スキルを検索")
    .navigationTitle("スキル")
    .navigationBarTitleDisplayMode(.inline)
  }
}
