import SwiftUI

struct SkillEditorView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var skill: MemoraSkill
  var reviewsAnswer = false
  @State private var keywords = ""
  @State private var failure = false

  var body: some View {
    let tools = model.toolRegistry().tools.values.filter { AgentTool(rawValue: $0.name) != nil }.sorted { $0.name < $1.name }
    let isNew = !model.customSkills.contains { $0.id == skill.id }
    NavigationStack {
      MemoraForm {
        Section {
          TextField("スキル名", text: $skill.name)
          TextField("いつ使うか・何をするか", text: $skill.summary, axis: .vertical)
        } footer: {
          Text("名前と用途、繰り返し使う作業手順を保存します。要約の書式だけを指定する場合はテンプレートを使います。")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
          TextEditor(text: $skill.instructions).frame(minHeight: 180).accessibilityLabel("スキルの手順")
        } header: {
          Text("手順")
        } footer: {
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            if reviewsAnswer {
              Text("回答を下書きとして取り込みました。今回だけの結果や個人情報を除き、次回も使える作業手順に編集してください。自動変換は行っていません。")
            }
            Text("目的の確認 → 作業の進め方 → 出力形式 → 確認事項の順に書くと再利用しやすくなります。")
            Text("\(skill.instructions.count) / 6,000文字")
          }
          .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
          TextField("キーワード（カンマ区切り・任意）", text: $keywords)
        } header: {
          Text("自動適用")
        } footer: {
          Text("依頼にスキル名やキーワードが含まれると自動で選択します。@で指定するか、詳細画面の「チャットで使用」から選ぶこともできます。")
            .font(.footnote).foregroundStyle(.secondary)
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
          Text("保存した手順は利用時に選択中のAIへ渡します。手順は権限や承認を変更しません。接続されていないサービスや無効なツールは実行できません。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle(isNew ? "スキルを作成" : "スキルを編集").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("キャンセル", role: .cancel) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            if model.saveCustomSkill(normalizedSkill) { dismiss() } else { failure = true }
          }
          .disabled(!MemoraSkillMarkdown.valid(normalizedSkill))
        }
      }
      .onAppear { keywords = skill.keywords.joined(separator: ", ") }
      .alert("スキルを保存できません", isPresented: $failure) { Button("閉じる", role: .cancel) {} } message: {
        Text("名前・用途・手順、最大16ツール・8キーワードを確認してください。カスタムスキルは最大30件です。保存先に問題がある場合も変更は確定しません。")
      }
    }
  }

  private var normalizedSkill: MemoraSkill {
    var candidate = skill
    candidate.name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate.summary = candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate.instructions = candidate.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate.keywords = keywords.components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    return candidate
  }
}
