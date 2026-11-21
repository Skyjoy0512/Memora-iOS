import SwiftUI

struct ConnectorHubView: View {
  @Environment(MemoraModel.self) private var model
  var query = ""
  @State private var selected: IntegrationCatalog?
  @State private var connectedIDs: Set<String> = []
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }
    let connected = services.filter { connectedIDs.contains($0.id) }
    let disconnected = services.filter { $0.isImplemented && !connectedIDs.contains($0.id) }
    let upcoming = services.filter { !$0.isImplemented }
    List {
      if !connected.isEmpty { Section("接続済み") { ForEach(connected) { row($0) } } }
      if !disconnected.isEmpty { Section("未接続") { ForEach(disconnected) { row($0) } } }
      Section {
        NavigationLink { MCPServersView() } label: {
          Label("カスタムコネクタを追加", icon: .plus)
            .frame(minHeight: MemoraSpacing.touchTarget)
        }
        NavigationLink { WebhookSettingsView() } label: {
          Label("Webhook", icon: .paperplane)
            .frame(minHeight: MemoraSpacing.touchTarget)
        }
      }
      if !upcoming.isEmpty { Section("準備中") { ForEach(upcoming) { row($0) } } }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("コネクタ")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: refreshConnections)
    .onChange(of: scenePhase) { _, phase in if phase == .active { refreshConnections() } }
    .sheet(item: $selected, onDismiss: refreshConnections) { ConnectorDetailSheet(service: $0) }
  }

  private func refreshConnections() {
    connectedIDs = Set(IntegrationCatalog.services.filter { model.integrationHasConnection($0.id) }.map(\.id))
  }

  private func row(_ service: IntegrationCatalog) -> some View {
    Button { selected = service } label: {
      HStack(spacing: MemoraSpacing.md) {
        AIPluginIconView(icon: .resolve(pluginID: "service:" + service.id, name: service.name), size: 25)
          .frame(width: MemoraSpacing.section, height: MemoraSpacing.section)
          .accessibilityHidden(true)
        Text(service.name)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(icon: .chevronRight, size: 14)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .frame(minHeight: MemoraSpacing.touchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(MemoraPalette.background)
    .accessibilityIdentifier("connector.\(service.id)")
  }
}
