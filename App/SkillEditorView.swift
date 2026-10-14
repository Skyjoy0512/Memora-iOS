import SwiftUI

struct SkillEditorView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var skill: MemoraSkill
  @State private var keywords = ""
  @State private var failure = false

  var body: some View {
    let tools = model.toolRegistry().tools.values.filter { AgentTool(rawValue: $0.name) != nil }.sorted { $0.name < $1.name }
    NavigationStack {
      Form {
        Section {
          TextField("スキル名", text: $skill.name)
          TextField("用途", text: $skill.summary, axis: .vertical)
          TextField("キーワード（カンマ区切り）", text: $keywords)
        }
        Section("手順") {
          TextEditor(text: $skill.instructions).frame(minHeight: 180).accessibilityLabel("スキルの手順")
        }
        Section {
          DisclosureGroup("利用するツール") {
            ForEach(tools) { tool in
              Toggle(isOn: Binding(get: { skill.toolNames.contains(tool.name) }, set: { enabled in
                var names = skill.toolNames
                names.removeAll { $0 == tool.name }
                if enabled { names.append(tool.name) }
                skill.declaredToolNames = names
              })) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(tool.name).font(.subheadline)
                  Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        } footer: {
          Text("手順は権限や承認を変更しません。接続されていないサービスや無効なツールは実行できません。")
        }
      }
      .navigationTitle("スキルを編集").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("キャンセル", role: .cancel) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            skill.name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            skill.summary = skill.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            skill.keywords = keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if model.saveCustomSkill(skill) { dismiss() } else { failure = true }
          }
        }
      }
      .onAppear { keywords = skill.keywords.joined(separator: ", ") }
      .alert("スキルを保存できません", isPresented: $failure) { Button("閉じる", role: .cancel) {} } message: {
        Text("名前・用途・手順、最大16ツール・8キーワードを確認してください。カスタムスキルは最大30件です。保存先に問題がある場合も変更は確定しません。")
      }
    }
  }
}
