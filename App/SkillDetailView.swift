import SwiftUI

struct SkillDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var skillID: String
  @State private var editing: MemoraSkill?
  @State private var deleting = false
  @State private var failure = false

  var body: some View {
    if let skill = model.skillCatalog.first(where: { $0.id == skillID }) {
      Form {
        Section {
          Label(skill.summary, icon: MemoraIcon(rawValue: skill.iconIdentifier ?? "") ?? .docText)
          LabeledContent("バージョン", value: String(skill.version ?? 1))
          LabeledContent("料金", value: (skill.cost ?? .unknown).rawValue)
          Toggle("有効", isOn: Binding(get: { !model.disabledSkillIDs.contains(skillID) }, set: { model.setSkillEnabled(skillID, enabled: $0) }))
          if let date = model.skillLastSelectedAt[skillID] { LabeledContent("最終選択", value: date.formatted(date: .abbreviated, time: .shortened)) }
        }
        Section("手順") { MarkdownDocumentView(markdown: skill.instructions) }
        Section {
          DisclosureGroup("利用ツールと権限") {
            ForEach(skill.toolNames, id: \.self) { Text($0).font(.subheadline) }
            ForEach(skill.declaredPermissions ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Text("記録のプライバシー・接続状態・料金・実行前の承認を適用します。宣言だけでは権限は付与されません。")
              .font(.footnote).foregroundStyle(.secondary)
          }
          ShareLink(item: skill.skillMarkdown) { Label("Markdownを共有", icon: .squareAndArrowUp) }
          if skill.id.hasPrefix("custom-") {
            Button("編集", icon: .pencil) { editing = skill }
            Button("スキルを削除", icon: .trash, role: .destructive) { deleting = true }
          }
        } footer: { Text("最終選択はAIへ補助手順を渡した履歴です。手順どおりに完了したことを保証する記録ではありません。カスタムスキルはMarkdownを共有して個別に保管できます。") }
      }
      .navigationTitle(skill.name).navigationBarTitleDisplayMode(.inline)
      .sheet(item: $editing) { SkillEditorView(skill: $0) }
      .confirmationDialog("このスキルを削除しますか？", isPresented: $deleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) { if model.deleteCustomSkill(skillID) { dismiss() } else { failure = true } }
      }
      .alert("削除できません", isPresented: $failure) { Button("閉じる", role: .cancel) {} }
    } else { ContentUnavailableView("スキルが見つかりません", icon: .docText) }
  }
}
