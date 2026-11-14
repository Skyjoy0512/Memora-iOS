import SwiftUI

struct SkillEditorView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var skill: MemoraSkill
  var reviewsAnswer = false
  @State private var keywords = ""
  @State private var failure = false
  @State private var originalSkill: MemoraSkill?
  @State private var confirmsDiscard = false
  @FocusState private var focusedField: Field?

  var body: some View {
    let tools = model.toolRegistry().tools.values.filter { AgentTool(rawValue: $0.name) != nil }.sorted { $0.name < $1.name }
    let isNew = !model.customSkills.contains { $0.id == skill.id }
    let input = SkillEditorInput(skill: skill, keywords: keywords)
    let hasChanges = input.hasChanges(from: originalSkill ?? skill)
    NavigationStack {
      MemoraForm {
        Section {
          TextField("スキル名", text: $skill.name)
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .summary }
          TextField("いつ使うか・何をするか", text: $skill.summary, axis: .vertical)
            .lineLimit(1...4)
            .focused($focusedField, equals: .summary)
        } footer: {
          Text(input.validationMessage ?? "保存した手順は、@やスキルの詳細から呼び出せます。")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("skill.validation")
        }
        Section {
          TextEditor(text: $skill.instructions).frame(minHeight: 180).accessibilityLabel("スキルの手順")
            .focused($focusedField, equals: .instructions)
            .overlay(alignment: .topLeading) {
              if skill.instructions.isEmpty {
                Text("目的・作業の進め方・出力形式・確認事項を書きます。")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 5).padding(.vertical, 8)
                  .allowsHitTesting(false).accessibilityHidden(true)
              }
            }
        } header: {
          Text("手順")
        } footer: {
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            if reviewsAnswer {
              Text("回答を下書きとして取り込みました。今回だけの結果や個人情報を除き、次回も使える作業手順に編集してください。自動変換は行っていません。")
            }
            Text("目的の確認 → 作業の進め方 → 出力形式 → 確認事項の順に書くと再利用しやすくなります。")
            Text("\(skill.instructions.count) / 6,000文字").monospacedDigit()
          }
          .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
          TextField("キーワード（カンマ区切り・任意）", text: $keywords)
            .focused($focusedField, equals: .keywords)
            .submitLabel(.done).onSubmit { focusedField = nil }
        } header: {
          Text("自動適用")
        } footer: {
          Text("依頼にスキル名やキーワードが含まれると自動で選択します。@で指定するか、詳細画面の「チャットで使用」から選ぶこともできます。")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("見つけやすさ（任意）") {
          Picker("用途", selection: $skill.category) {
            Text("未指定").tag(Optional<MemoraSkill.Category>.none)
            ForEach(MemoraSkill.Category.allCases, id: \.self) {
              Text($0.title).tag(Optional($0))
            }
          }
          TextField("できあがるもの", text: Binding(
            get: { skill.outputDescription ?? "" },
            set: { skill.outputDescription = $0.isEmpty ? nil : $0 }), axis: .vertical)
          TextField("依頼の例（1行に1つ、3件まで）", text: Binding(
            get: { (skill.examplePrompts ?? []).joined(separator: "\n") },
            set: { skill.examplePrompts = $0.isEmpty ? nil : $0.components(separatedBy: "\n") }), axis: .vertical)
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
        ToolbarItem(placement: .cancellationAction) {
          // Let the editor decide whether cancellation needs confirmation.
          Button("キャンセル") {
            focusedField = nil
            if hasChanges { confirmsDiscard = true } else { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            focusedField = nil
            if model.saveCustomSkill(input.normalizedSkill) { dismiss() } else { failure = true }
          }
          .disabled(input.validationMessage != nil)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完了") { focusedField = nil }
        }
      }
      .interactiveDismissDisabled(hasChanges)
      .onAppear {
        guard originalSkill == nil else { return }
        originalSkill = skill
        keywords = skill.keywords.joined(separator: ", ")
      }
      .alert("変更を破棄しますか？", isPresented: $confirmsDiscard) {
        Button("編集を続ける", role: .cancel) {}
        Button("変更を破棄", role: .destructive) { dismiss() }
      } message: {
        Text("まだ保存されていない変更だけを破棄します。保存済みのスキルは変更しません。")
      }
      .alert("スキルを保存できません", isPresented: $failure) { Button("閉じる", role: .cancel) {} } message: {
        Text("名前・用途・手順、最大16ツール・8キーワードを確認してください。カスタムスキルは最大30件です。保存先に問題がある場合も変更は確定しません。")
      }
    }
  }

  private enum Field: Hashable { case name, summary, instructions, keywords }
}
