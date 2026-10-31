import SwiftUI

struct ConnectorHubView: View {
  @Environment(MemoraModel.self) private var model
  var query = ""
  var showsIntroduction = true
  @State private var selected: IntegrationCatalog?
  @State private var connectedIDs: Set<String> = []
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let services = IntegrationCatalog.services.filter {
      ToolsCatalogSearch.matches(query, fields: [$0.name, $0.summary] + $0.aliases)
    }
    let connected = services.filter { connectedIDs.contains($0.id) }
    let available = services.filter { $0.isImplemented && !connectedIDs.contains($0.id) }
    let upcoming = services.filter { !$0.isImplemented }
    List {
      if showsIntroduction && query.isEmpty {
        Section {
          VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
              ForEach(["gmail", "calendar", "notion"], id: \.self) { id in
                if let service = IntegrationCatalog.services.first(where: { $0.id == id }) {
                  AIPluginIconView(icon: .resolve(pluginID: "service:" + id, name: service.name), size: 34)
                    .frame(width: 64, height: 64)
                    .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 18))
                }
              }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).accessibilityHidden(true)
            Text("Ask AIとツールをつなぐ").font(.title2.weight(.semibold))
            Text("予定やメールを参照し、会話から次の作業へ。")
              .font(.subheadline).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }.listRowBackground(Color.clear)
      }
      if query.isEmpty || !connected.isEmpty {
        Section("接続済み") {
          if connected.isEmpty {
            VStack(spacing: 8) {
              Image(icon: .plugsConnected, size: 28).accessibilityHidden(true)
              Text("まだ接続されていません").font(.headline)
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
          } else { ForEach(connected) { row($0) } }
        }
      }
      if !available.isEmpty { Section("おすすめ") { ForEach(available) { row($0) } } }
      if !upcoming.isEmpty { Section("準備中") { ForEach(upcoming) { row($0) } } }
      Section {
        NavigationLink { MCPServersView() } label: {
          Label("カスタムコネクタを追加", icon: .plus).frame(minHeight: 44)
        }
        NavigationLink { WebhookSettingsView() } label: { Label("Webhook", icon: .paperplane) }
      }
    }
    .listStyle(.insetGrouped)
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
    let ready = connectedIDs.contains(service.id)
    return Button { selected = service } label: {
      HStack(spacing: 14) {
        AIPluginIconView(icon: .resolve(pluginID: "service:" + service.id, name: service.name), size: 25)
          .frame(width: 48, height: 48).background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 13))
        Text(service.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
        Text(!service.isImplemented ? "準備中" : ready ? "管理" : "接続")
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 13).padding(.vertical, 8)
          .background(MemoraPalette.selection, in: Capsule())
      }.padding(.vertical, 4).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("connector.\(service.id)")
  }
}
