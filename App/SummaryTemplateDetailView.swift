import SwiftUI

struct SummaryTemplateDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var templateID: String
  @State private var editing: SummaryMarketTemplate?
  @State private var isConfirmingDelete = false

  var body: some View {
    if let template = model.customTemplates.first(where: { $0.id == templateID })
      ?? SummaryTemplateCatalog.template(id: templateID) {
      let isAdded = model.isTemplateAvailable(template.id)
      let isDefault = !model.followsOccupationSummaryTemplates && model.defaultSummaryChoice.id == template.id
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.section) {
          TemplateArticleHeader(template: template)
          Divider()
          TemplateArticleContent(template: template)
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.xxl)
        .padding(.top, MemoraSpacing.section)
        .padding(.bottom, MemoraSpacing.section)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .background(MemoraPalette.background)
      .navigationTitle("テンプレート")
      .navigationBarTitleDisplayMode(.inline)
      .tint(MemoraPalette.textPrimary)
      .navigationBarBackButtonHidden(true)
      .toolbarBackground(MemoraPalette.background, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: MemoraSpacing.sm) {
          ToolsPrimaryAction(title: isDefault ? "自動生成の既定を解除" : "自動生成に使用") {
            if isDefault {
              model.useOccupationSummaryTemplates()
            } else {
              if !isAdded { model.installTemplate(template.id) }
              model.setDefaultSummaryTemplate(template.id)
            }
          }
          Text(isDefault ? "自動生成はこのテンプレートで要約します。" : "要約時の選択肢にも追加されます。")
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, MemoraSpacing.xxl)
        .padding(.vertical, MemoraSpacing.md)
        .background(MemoraPalette.background)
      }
      .toolbar {
        ToolbarActionItem(placement: .topBarLeading) {
          ToolbarIconButton("1つ前に戻る", icon: .chevronLeft) { dismiss() }
        }
        ToolbarActionItem {
          Menu {
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
          } label: { ToolbarActionLabel("テンプレートの操作", icon: .ellipsis) }
        }
      }
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
}

private struct TemplateArticleHeader: View {
  var template: SummaryMarketTemplate

  var body: some View {
    VStack(spacing: MemoraSpacing.md) {
      Image(icon: template.symbol, size: 28).accessibilityHidden(true)
      Text(template.title).font(.title.weight(.semibold)).multilineTextAlignment(.center)
      Text(template.isCustom ? "マイテンプレート" : template.category.title)
        .font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, MemoraSpacing.sm)
  }
}

private struct TemplateArticleContent: View {
  var template: SummaryMarketTemplate

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.section) {
      if !template.detail.isEmpty {
        VStack(alignment: .leading, spacing: MemoraSpacing.md) {
          Text("説明").font(.title3.weight(.semibold))
          Text(template.detail).lineSpacing(MemoraTypography.readingLineSpacing)
        }
      }
      VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
        Text(template.usesPrompt ? "プロンプト" : "チャプター").font(.title3.weight(.semibold))
        if template.usesPrompt {
          Text(template.prompt)
            .lineSpacing(MemoraTypography.readingLineSpacing)
        } else {
          Text("概要").font(.title2.weight(.semibold))
          Text("この観点で重要なことを3〜5文でまとめます。")
          ForEach(template.sections, id: \.self) { section in
            Text(section).font(.headline)
          }
        }
        if template.includesActions {
          Text("アクションアイテム").font(.headline)
          Text("会議で示された担当と期限を整理し、タスクに追加します。")
            .foregroundStyle(.secondary)
        }
      }
      if !template.focus.isEmpty {
        VStack(alignment: .leading, spacing: MemoraSpacing.md) {
          Text("注目すること").font(.title3.weight(.semibold))
          Text(template.focus).lineSpacing(MemoraTypography.readingLineSpacing)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }
}
