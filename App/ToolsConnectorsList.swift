import SwiftUI

struct ToolsConnectorsList: View {
  var body: some View {
    let services = IntegrationCatalog.services
    let groups: [(String, [IntegrationCatalog])] = [
      ("コミュニケーション", services.filter { $0.id == "gmail" }),
      ("カレンダー", services.filter { $0.id == "calendar" }),
      ("ナレッジ", services.filter { ["notion", "drive"].contains($0.id) }),
      ("開発", services.filter { $0.id == "github" }),
      ("拡張", services.filter { $0.id == "mcp" })
    ]
    List {
      ForEach(groups, id: \.0) { title, services in
        Section {
          ForEach(services) { service in ToolsConnectorRow(service: service) }
        } header: { ToolsSectionHeading(title: title) }
      }
      Section {
        NavigationLink { WebhookSettingsView() } label: {
          SettingsLabel("Webhook", icon: .paperplane)
        }
        .listRowBackground(MemoraPalette.background)
        NavigationLink { IOSIntegrationSettingsView() } label: {
          SettingsLabel("ウィジェットとショートカット", icon: .rectangleStack)
        }
        .listRowBackground(MemoraPalette.background)
      } header: { ToolsSectionHeading(title: "自動化とシステム") }
    }
  }
}

private struct ToolsConnectorRow: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
  var service: IntegrationCatalog

  var body: some View {
    let state = model.integrationState(service)
    NavigationLink { IntegrationDetailView(service: service) } label: {
      HStack(spacing: MemoraSpacing.lg) {
        AIPluginIconView(icon: .resolve(pluginID: "service:" + service.id, name: service.name), size: 28)
          .frame(width: 28, height: 32)
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
          Text(service.name).font(.body)
          if typeSize.isAccessibilitySize {
            ToolsConnectorStatus(isReady: state.isReady, isImplemented: service.isImplemented)
          }
        }
        Spacer(minLength: MemoraSpacing.sm)
        if !typeSize.isAccessibilitySize {
          ToolsConnectorStatus(isReady: state.isReady, isImplemented: service.isImplemented)
        }
      }
      .padding(.vertical, MemoraSpacing.sm)
    }
    .listRowBackground(MemoraPalette.background)
  }
}

private struct ToolsConnectorStatus: View {
  var isReady: Bool
  var isImplemented: Bool

  var body: some View {
    if isReady {
      Text("接続済み")
        .font(.caption)
        .foregroundStyle(MemoraPalette.success)
        .padding(.horizontal, MemoraSpacing.sm)
        .padding(.vertical, MemoraSpacing.xs)
        .background(MemoraPalette.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    } else if !isImplemented {
      Text("未対応").font(.caption).foregroundStyle(.secondary)
    }
  }
}
