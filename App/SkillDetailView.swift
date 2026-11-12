import SwiftUI

struct SkillDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var skillID: String
  var isMarketplaceSheet = false
  @State private var editing: MemoraSkill?
  @State private var deleting = false
  @State private var failure = false
  @State private var publishes = false

  var body: some View {
    if let skill = model.skillCatalog.first(where: { $0.id == skillID }) {
      let enabled = !model.disabledSkillIDs.contains(skillID)
      let provider = skill.id.hasPrefix("custom-") ? "マイスキル" : "Memora"
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.section) {
          MarketplaceDetailHero(item: .skill(skill), subtitle: "提供: \(provider)") { EmptyView() }
          MarketplaceDescription(text: skill.summary)
          MarketplaceDetailFacts(fields: [
            ("利用状況", enabled ? "有効" : "無効"), ("カテゴリー", "スキル"),
            ("提供", provider), ("バージョン", String(skill.version ?? 1))
          ])
          Menu {
            Button("コミュニティに投稿", icon: .squareAndArrowUp) { publishes = true }
            ShareLink(item: MarketplaceDefinition(skill: skill).shareText) { Label("スキルを共有", icon: .squareAndArrowUp) }
            ShareLink(item: skill.skillMarkdown) { Label("Markdownを共有", icon: .squareAndArrowUp) }
            if skill.id.hasPrefix("custom-") {
              Button("編集", icon: .pencil) { editing = skill }
              Button("スキルを削除", icon: .trash, role: .destructive) { deleting = true }
            }
          } label: {
            Label(skill.id.hasPrefix("custom-") ? "共有・編集" : "共有", icon: .ellipsis)
              .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
              .contentShape(Rectangle())
          }
          .accessibilityLabel("スキルの操作")
          VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
            Text("使い方").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            MarkdownDocumentView(markdown: skill.instructions)
          }
          .textSelection(.enabled)
          SkillArticleSettings(skill: skill)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.xl)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        MarketplaceDetailFooter {
          Button { useSkill() } label: {
            MarketplaceDetailActionLabel(title: enabled ? "チャットで使用" : "有効にしてチャットで使用")
          }
          .accessibilityIdentifier("marketplace.detail.useSkill")
        }
      }
      .background(MemoraPalette.background)
      .navigationTitle(skill.name)
      .navigationBarTitleDisplayMode(.inline)
      .tint(MemoraPalette.textPrimary)
      .navigationBarBackButtonHidden(true)
      .sheet(isPresented: $publishes) { CommunityPublishSheet(definition: .init(skill: skill)) }
      .toolbar {
        ToolbarActionItem(placement: .topBarLeading) {
          ToolbarIconButton(isMarketplaceSheet ? "閉じる" : "1つ前に戻る", icon: .chevronLeft) { dismiss() }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          ShareLink(item: MarketplaceDefinition(skill: skill).shareText) {
            ToolbarActionLabel("スキルを共有", icon: .squareAndArrowUp)
          }
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

  private func useSkill() {
    if model.disabledSkillIDs.contains(skillID) { model.setSkillEnabled(skillID, enabled: true) }
    dismiss()
    model.prepareSkillInComposer(skillID)
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
          LabeledContent("最終選択", value: date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))
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
