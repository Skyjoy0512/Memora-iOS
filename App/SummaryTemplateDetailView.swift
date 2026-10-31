import SwiftUI

struct SummaryTemplateDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var templateID: String
  var isMarketplaceSheet = false
  @State private var editing: SummaryMarketTemplate?
  @State private var isConfirmingDelete = false
  @State private var publishes = false

  var body: some View {
    if let template = model.customTemplates.first(where: { $0.id == templateID })
      ?? SummaryTemplateCatalog.template(id: templateID) {
      let isAdded = model.isTemplateAvailable(template.id)
      let isDefault = !model.followsOccupationSummaryTemplates && model.defaultSummaryChoice.id == template.id
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.section) {
          MarketplaceDetailHero(item: .template(template), subtitle: "\(template.isCustom ? "マイテンプレート" : "Memora") · 要約テンプレート") {
            Button {
              if isDefault { model.useOccupationSummaryTemplates() }
              else {
                if !isAdded { model.installTemplate(template.id) }
                model.setDefaultSummaryTemplate(template.id)
              }
            } label: {
              MarketplaceDetailActionLabel(title: isDefault ? "自動生成の既定を解除" : "自動生成に使用", icon: isDefault ? .checkmark : .arrowUpRight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("marketplace.detail.useTemplate")
          }
          MarketplaceDetailFacts(fields: [
            ("カテゴリー", template.category.title), ("利用状況", isDefault ? "自動生成の既定" : isAdded ? "追加済み" : "未追加"),
            ("タスク抽出", template.includesActions ? "あり" : "なし"), ("提供", template.isCustom ? "マイテンプレート" : "Memora")
          ])
          if !template.detail.isEmpty { Text(template.detail).memoraReadingText().textSelection(.enabled) }
          templateActions(template: template, isAdded: isAdded)
          TemplateArticleContent(template: template)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.xl)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .background(MemoraPalette.background)
      .navigationTitle(template.title)
      .navigationBarTitleDisplayMode(.inline)
      .tint(MemoraPalette.textPrimary)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarActionItem(placement: .topBarLeading) {
          ToolbarIconButton(isMarketplaceSheet ? "閉じる" : "1つ前に戻る", icon: isMarketplaceSheet ? .xmark : .chevronLeft) { dismiss() }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          ToolbarIconButton(isAdded ? "追加済み" : "要約の選択肢に追加", icon: isAdded ? .checkmark : .plus) {
            model.installTemplate(template.id)
          }
          .disabled(isAdded)
          .accessibilityIdentifier("marketplace.detail.addTemplate")
        }
      }
      .sheet(isPresented: $publishes) { CommunityPublishSheet(definition: .init(template: template)) }
      .sheet(item: $editing) { SummaryTemplateEditor(template: $0) }
      .confirmationDialog("「\(template.title)」を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteCustomTemplate(template.id)
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      } message: { Text("作成済みの要約はそのまま残ります。") }
    } else {
      ContentUnavailableView("テンプレートが見つかりません", icon: .docQuestionmark)
    }
  }

  private func templateActions(template: SummaryMarketTemplate, isAdded: Bool) -> some View {
    Menu {
      ShareLink(item: MarketplaceDefinition(template: template).shareText) { Label("テンプレートを共有", icon: .squareAndArrowUp) }
      Button("コミュニティに投稿", icon: .squareAndArrowUp) { publishes = true }
      if template.isCustom {
        Button("編集", icon: .pencil) { editing = template }
        Button("削除", icon: .trash, role: .destructive) { isConfirmingDelete = true }
      } else {
        Button("これをもとに自分用を作る", icon: .squareAndPencil) {
          var copy = template
          copy.id = "custom.\(UUID().uuidString)"
          copy.title = "\(template.title)（自分用）"
          copy.isCustom = true
          editing = copy
        }
        if isAdded {
          Button("要約の選択肢から外す", icon: .minusCircle, role: .destructive) {
            model.uninstallTemplate(template.id)
          }
        } else {
          Button("要約の選択肢に追加", icon: .plus) { model.installTemplate(template.id) }
        }
      }
    } label: {
      Label("共有・編集", icon: .ellipsis)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("テンプレートの操作")
  }
}

private struct TemplateArticleContent: View {
  var template: SummaryMarketTemplate

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.section) {
      VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
        Text(template.usesPrompt ? "プロンプト" : "まとめる項目").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if template.usesPrompt {
          Text(template.prompt).memoraReadingText()
        } else {
          Text("概要").font(.headline)
          ForEach(template.sections, id: \.self) { section in
            Text(section).font(.headline)
          }
        }
        if template.includesActions {
          Text("アクションアイテム").font(.headline)
          Text("会議で示された担当と期限を整理し、タスクに追加します。")
            .memoraReadingText()
            .foregroundStyle(.secondary)
        }
      }
      if !template.focus.isEmpty {
        VStack(alignment: .leading, spacing: MemoraSpacing.md) {
          Text("注目すること").font(.title3.weight(.semibold))
          Text(template.focus).memoraReadingText()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }
}
