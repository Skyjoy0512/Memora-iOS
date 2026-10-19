import SwiftUI

/// One template: what it is for, the outline a summary written with it has,
/// and adding it, making it the default, or editing the person's own.
struct SummaryTemplateDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var templateID: String
  @State private var editing: SummaryMarketTemplate?
  @State private var isConfirmingDelete = false

  var body: some View {
    if let template = model.customTemplates.first(where: { $0.id == templateID })
      ?? SummaryTemplateCatalog.template(id: templateID) {
      content(template)
    } else {
      ContentUnavailableView("テンプレートが見つかりません", icon: .docQuestionmark)
    }
  }

  private func content(_ template: SummaryMarketTemplate) -> some View {
    let isAdded = model.isTemplateAvailable(template.id)
    let isDefault = !model.followsOccupationSummaryTemplates && model.defaultSummaryChoice.id == template.id

    return List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Image(icon: template.symbol)
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 52, height: 52)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
          Text(template.title)
            .font(.title2.bold())
          if !template.detail.isEmpty {
            Text(template.detail)
              .foregroundStyle(.secondary)
          }
          Text(template.isCustom ? "マイテンプレート" : template.category.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, MemoraSpacing.sm)
      }

      if template.usesPrompt {
        Section {
          Text(template.prompt)
            .textSelection(.enabled)
        } header: {
          Text("プロンプト")
        } footer: {
          Text(template.includesActions ? "最後にアクションアイテムを付け、タスクに追加します。" : "")
        }
      } else {
        Section {
          outlineRow("概要", detail: "この観点で重要なことを3〜5文")
          ForEach(template.sections, id: \.self) { section in
            outlineRow(section, detail: nil)
          }
          if template.includesActions {
            outlineRow("アクションアイテム", detail: "担当と期限つき。タスクに追加されます")
          }
        } header: {
          Text("できあがる要約の構成")
        } footer: {
          if !template.focus.isEmpty {
            Text("注目すること: \(template.focus)")
          }
        }
      }

      Section {
        if template.isCustom {
          Button("編集", icon: .pencil) { editing = template }
        } else {
          Button("これをもとに自分用を作る", icon: .squareAndPencil) {
            var copy = template
            copy.id = "custom.\(UUID().uuidString)"
            copy.title = "\(template.title)（自分用）"
            copy.isCustom = true
            editing = copy
          }
        }

        if !template.isCustom {
          if isAdded {
            Button("要約の選択肢から外す", icon: .minusCircle, role: .destructive) {
              model.uninstallTemplate(template.id)
            }
          } else {
            Button("追加", icon: .plusCircle) {
              model.installTemplate(template.id)
            }
          }
        }

        if isAdded || template.isCustom {
          Button(isDefault ? "既定を解除" : "自動生成の既定にする", icon: .starFill) {
            if isDefault { model.useOccupationSummaryTemplates() }
            else { model.setDefaultSummaryTemplate(template.id) }
          }
        }

        if template.isCustom {
          Button("削除", icon: .trash, role: .destructive) {
            isConfirmingDelete = true
          }
        }
      } footer: {
        Text(isDefault
             ? "自動生成はこのテンプレートで要約します。"
             : "追加すると、要約を生成するときの選択肢に加わります。")
      }
    }
    .navigationTitle(template.title)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { template in
      SummaryTemplateEditor(template: template)
    }
    .confirmationDialog("「\(template.title)」を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        model.deleteCustomTemplate(template.id)
        dismiss()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("作成済みの要約はそのまま残ります。")
    }
  }

  private func outlineRow(_ title: String, detail: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("##")
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body.weight(.medium))
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
