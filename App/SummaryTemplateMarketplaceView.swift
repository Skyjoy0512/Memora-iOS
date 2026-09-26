import SwiftUI

/// Adds and removes the summary templates that go beyond the built-ins. Added
/// templates join the picker in the summary sheet.
struct SummaryTemplateMarketplaceView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    List {
      Section {
        ForEach(SummaryTemplateCatalog.market) { template in
          row(template)
        }
      } header: {
        Text("追加できるテンプレート")
      } footer: {
        Text("追加したテンプレートは、要約を生成するときの選択肢に加わります。")
      }
    }
    .navigationTitle("要約テンプレート")
    .memoraBackButton()
  }

  private func row(_ template: SummaryMarketTemplate) -> some View {
    let isInstalled = model.installedTemplateIDs.contains(template.id)

    return HStack(spacing: 14) {
      Image(icon: template.symbol)
        .font(.headline)
        .frame(width: 38, height: 38)
        .background(Color.primary.opacity(0.07), in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(template.title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(template.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      Button(isInstalled ? "削除" : "追加") {
        if isInstalled {
          model.uninstallTemplate(template.id)
        } else {
          model.installTemplate(template.id)
        }
      }
      .buttonStyle(.bordered)
      .tint(isInstalled ? .gray : nil)
      .accessibilityLabel(isInstalled ? "\(template.title)を削除" : "\(template.title)を追加")
    }
    .padding(.vertical, 4)
  }
}
