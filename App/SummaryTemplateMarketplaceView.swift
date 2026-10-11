import SwiftUI

/// The template marketplace: templates for everyday business conversations,
/// grouped by kind, plus the person's own. Added templates join the choices
/// when a summary is generated, and one can be the default.
struct SummaryTemplateMarketplaceView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var editing: SummaryMarketTemplate?

  var body: some View {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matching = SummaryTemplateCatalog.market.filter { Self.matches($0, trimmed) }
    let custom = model.customTemplates.filter { Self.matches($0, trimmed) }
    let recommendations = model.recommendedSummaryChoices.compactMap { choice -> SummaryMarketTemplate? in
      if case .market(let template) = choice, Self.matches(template, trimmed) { return template }
      return nil
    }

    List {
      if !recommendations.isEmpty {
        Section("仕事・活動からのおすすめ") {
          ForEach(recommendations) { row($0) }
        }
      }
      if trimmed.isEmpty {
        Section {
          LabeledContent("自動生成で使う", value: model.defaultSummaryChoice.title)
        } footer: {
          Text("仕事・活動はおすすめの順序に使います。要約方法は「パーソナライズ」の要約スタイルで変更できます。すべてのテンプレートを選べます。")
        }
      }

      Section {
        ForEach(custom) { template in
          row(template)
        }
        if trimmed.isEmpty {
          Button("テンプレートを作成", icon: .plus) {
            editing = SummaryMarketTemplate(
              id: "custom.\(UUID().uuidString)",
              title: "",
              detail: "",
              symbol: .docText,
              lead: "",
              isCustom: true
            )
          }
        }
      } header: {
        Text("マイテンプレート")
      }

      ForEach(SummaryTemplateCategory.allCases) { category in
        let templates = matching.filter { $0.category == category }
        if !templates.isEmpty {
          Section(category.title) {
            ForEach(templates) { template in
              row(template)
            }
          }
        }
      }
    }
    .navigationTitle("要約テンプレート")
    .memoraBackButton()
    .searchable(text: $query, prompt: "テンプレートを検索")
    .overlay {
      if !trimmed.isEmpty, matching.isEmpty, custom.isEmpty {
        ContentUnavailableView.search(text: trimmed)
      }
    }
    .sheet(item: $editing) { template in
      SummaryTemplateEditor(template: template)
    }
  }

  private static func matches(_ template: SummaryMarketTemplate, _ query: String) -> Bool {
    guard !query.isEmpty else { return true }
    return [template.title, template.detail, template.category.title]
      .contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func row(_ template: SummaryMarketTemplate) -> some View {
    let isAdded = model.isTemplateAvailable(template.id)
    let isDefault = model.defaultTemplateID == template.id

    return NavigationLink {
      SummaryTemplateDetailView(templateID: template.id)
    } label: {
      HStack(spacing: 14) {
        Image(icon: template.symbol)
          .font(.headline)
          .foregroundStyle(.tint)
          .frame(width: 38, height: 38)
          .background(Color.accentColor.opacity(0.1), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(template.title)
              .font(.headline)
              .foregroundStyle(.primary)
            if isDefault {
              Text("既定")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.15), in: Capsule())
                .foregroundStyle(.tint)
            }
          }
          Text(template.detail.isEmpty ? template.sections.joined(separator: "・") : template.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer(minLength: 8)

        if isAdded {
          Image(icon: .checkmarkCircleFill)
            .foregroundStyle(.tint)
            .accessibilityLabel("追加済み")
        }
      }
      .padding(.vertical, 2)
    }
  }
}
