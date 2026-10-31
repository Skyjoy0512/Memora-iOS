import SwiftUI

struct IntegrationDetailView: View {
  @Environment(MemoraModel.self) private var model
  var service: IntegrationCatalog

  var body: some View {
    let state = model.integrationState(service)
    MemoraForm {
      Section {
        IntegrationArticleHeader(service: service, status: service.isImplemented ? state.label : "準備中")
        if service.isImplemented { Text(service.summary).font(.subheadline).foregroundStyle(.secondary) }
      }
      if service.isImplemented {
        Section { IntegrationArticleControls(service: service) }
        Section {
          DisclosureGroup("連携の詳細") {
            Text(service.permissions).font(.subheadline)
            if let reason = state.reason { Text(reason).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(service.toolNames, id: \.self) { name in
              if let tool = AgentTool(rawValue: name) { Text(tool.summary).font(.subheadline) }
            }
          }
        }
      }
    }

    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle(service.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MemoraPalette.background, for: .navigationBar)
  }
}

private struct IntegrationArticleHeader: View {
  var service: IntegrationCatalog
  var status: String

  var body: some View {
    HStack(spacing: MemoraSpacing.lg) {
      AIPluginIconView(icon: .resolve(pluginID: "service:" + service.id, name: service.name), size: 36)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(service.name).font(.title2.weight(.semibold))
        Text(status).font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
      }
    }
  }
}

private struct IntegrationArticleControls: View {
  @Environment(MemoraModel.self) private var model
  var service: IntegrationCatalog

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      Toggle("AIで使う", isOn: Binding(
        get: { model.integrationIsEnabled(service.id) },
        set: { model.setIntegrationEnabled(service.id, enabled: $0) }))
        .frame(minHeight: 44)
      switch service.id {
      case "gmail":
        NavigationLink { GmailSettingsView() } label: { IntegrationSetupLabel(title: "接続を設定") }
      case "notion":
        NavigationLink { NotionSettingsView() } label: { IntegrationSetupLabel(title: "接続を設定") }
      case "mcp":
        NavigationLink { MCPServersView() } label: { IntegrationSetupLabel(title: "接続先を管理") }
      case "calendar":
        if CalendarService.access != .granted {
          Button("カレンダーへのアクセスを許可") { Task { _ = await CalendarService.requestAccess() } }
            .buttonStyle(MemoraButtonStyle())
        }
      default: EmptyView()
      }
    }
  }
}

private struct IntegrationSetupLabel: View {
  var title: String

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
        .foregroundStyle(MemoraPalette.textSecondary)
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}
