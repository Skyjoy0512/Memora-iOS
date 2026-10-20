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
      let enabled = !model.disabledSkillIDs.contains(skillID)
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.section) {
          SkillArticleHeader(skill: skill)
          SkillArticleInstructions(summary: skill.summary, instructions: skill.instructions)
          SkillArticleSettings(skill: skill)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.xxl)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .background(MemoraPalette.background)
      .navigationTitle("スキル")
      .navigationBarTitleDisplayMode(.inline)
      .tint(MemoraPalette.textPrimary)
      .navigationBarBackButtonHidden(true)
      .toolbarBackground(MemoraPalette.background, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        ToolsPrimaryAction(title: enabled ? "チャットで使用" : "スキルを有効にする") {
          if enabled {
            model.prepareSkillInComposer(skillID)
          } else {
            model.setSkillEnabled(skillID, enabled: true)
          }
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .frame(maxWidth: MemoraSpacing.readingWidth + MemoraSpacing.screen * 2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoraSpacing.md)
        .background(MemoraPalette.background)
      }
      .toolbar {
        ToolbarActionItem(placement: .topBarLeading) {
          ToolbarIconButton("1つ前に戻る", icon: .chevronLeft) { dismiss() }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            ShareLink(item: skill.skillMarkdown) { Label("Markdownを共有", icon: .squareAndArrowUp) }
            if skill.id.hasPrefix("custom-") {
              Button("編集", icon: .pencil) { editing = skill }
              Button("スキルを削除", icon: .trash, role: .destructive) { deleting = true }
            }
          } label: { ToolbarActionLabel("スキルの操作", icon: .ellipsis) }
        }
      }
      .sheet(item: $editing) { SkillEditorView(skill: $0) }
      .confirmationDialog("このスキルを削除しますか？", isPresented: $deleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          if model.deleteCustomSkill(skillID) { dismiss() } else { failure = true }
        }
      }
      .alert("削除できません", isPresented: $failure) { Button("閉じる", role: .cancel) {} }
    } else {
      ContentUnavailableView("スキルが見つかりません", icon: .docText)
    }
  }
}

private struct SkillArticleHeader: View {
  var skill: MemoraSkill

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
      Text(skill.name).font(MemoraTypography.screenTitle)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
        LabeledContent("提供", value: skill.id.hasPrefix("custom-") ? "自分で作成" : "Memora")
        LabeledContent("バージョン", value: String(skill.version ?? 1))
      }
      .font(.subheadline)
      .foregroundStyle(MemoraPalette.textSecondary)
      .padding(.leading, MemoraSpacing.md)
      .overlay(alignment: .leading) { Rectangle().fill(MemoraPalette.border).frame(width: 2) }
    }
  }
}

private struct SkillArticleInstructions: View {
  var summary: String
  var instructions: String

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.section) {
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("目的とシナリオ").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        Text(summary).memoraReadingText()
      }
      VStack(alignment: .leading, spacing: MemoraSpacing.md) {
        Text("仕組み").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        MarkdownDocumentView(markdown: instructions)
      }
    }
    .textSelection(.enabled)
  }
}

private struct SkillArticleSettings: View {
  @Environment(MemoraModel.self) private var model
  var skill: MemoraSkill

  var body: some View {
    DisclosureGroup("利用設定と権限") {
      VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
        Toggle("有効", isOn: Binding(
          get: { !model.disabledSkillIDs.contains(skill.id) },
          set: { model.setSkillEnabled(skill.id, enabled: $0) }))
        LabeledContent("料金", value: (skill.cost ?? .unknown).rawValue)
        if let date = model.skillLastSelectedAt[skill.id] {
          LabeledContent("最終選択", value: date.formatted(date: .abbreviated, time: .shortened))
        }
        ForEach(skill.toolNames, id: \.self) { Text($0).font(.subheadline.monospaced()) }
        ForEach(skill.declaredPermissions ?? [], id: \.self) { Text($0).font(.footnote) }
        Text("記録のプライバシー・接続状態・料金・実行前の承認を適用します。宣言だけでは権限は付与されません。最終選択はAIへ手順を渡した履歴で、完了を保証するものではありません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .padding(.top, MemoraSpacing.lg)
    }
    .padding(.top, MemoraSpacing.sm)
  }
}
