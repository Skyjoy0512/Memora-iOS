import SwiftUI

struct ToolsConnectorsList: View {
  @Binding var query: String
  var body: some View {
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }
    let showsWebhook = ToolsCatalogSearch.matches(query, fields: ["Webhook", "通知", "自動化"])
    let showsSystem = ToolsCatalogSearch.matches(query, fields: ["ウィジェットとショートカット", "システム", "Widget", "Shortcuts"])
    let groups: [(String, [IntegrationCatalog])] = [
      ("接続できるサービス", services.filter(\.isImplemented)),
      ("準備中", services.filter { !$0.isImplemented })
    ]
    List {
      ForEach(groups, id: \.0) { title, services in
        if !services.isEmpty {
          Section {
            ForEach(services) { service in ToolsConnectorRow(service: service) }
          } header: { ToolsSectionHeading(title: title) }
        }
      }
      if showsWebhook || showsSystem {
        Section {
          if showsWebhook {
            NavigationLink { WebhookSettingsView() } label: {
              SettingsLabel("Webhook", icon: .paperplane)
            }
            .listRowBackground(MemoraPalette.background)
          }
          if showsSystem {
            NavigationLink { IOSIntegrationSettingsView() } label: {
              SettingsLabel("ウィジェットとショートカット", icon: .rectangleStack)
            }
            .listRowBackground(MemoraPalette.background)
          }
        } header: { ToolsSectionHeading(title: "自動化とシステム") }
      }
    }
    .overlay(alignment: .top) {
      if services.isEmpty && !showsWebhook && !showsSystem {
        ToolsSearchEmptyState { query = "" }
      }
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
    } else {
      Text(isImplemented ? "未接続" : "準備中").font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
