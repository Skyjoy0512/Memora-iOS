import SwiftUI

struct IntegrationDetailView: View {
  @Environment(MemoraModel.self) private var model
  var service: IntegrationCatalog
  @State private var permissionFailure = false
  @State private var connected = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let state = model.integrationState(service)
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(spacing: 18) {
          AIPluginIconView(icon: .resolve(pluginID: "service:" + service.id, name: service.name), size: 54)
            .frame(width: 100, height: 100)
            .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 28))
          Text(service.name).font(.title.weight(.semibold)).multilineTextAlignment(.center)
          Text(service.isImplemented ? (connected ? "接続済み" : state.label) : "準備中").font(.subheadline).foregroundStyle(.secondary)
          if service.isImplemented { connectionAction(ready: connected) }
        }.frame(maxWidth: .infinity)

        Text(service.summary).font(.body).foregroundStyle(.secondary)
        if service.isImplemented {
          VStack(alignment: .leading, spacing: 16) {
            Text("このコネクタでできること").font(.headline)
            ForEach(service.capabilities, id: \.self) { capability in
              Label(capability, icon: .checkmark).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(20).frame(maxWidth: .infinity, alignment: .leading)
          .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 20))
          if connected {
            Toggle("Ask AIで使う", isOn: Binding(
              get: { model.integrationIsEnabled(service.id) },
              set: { model.setIntegrationEnabled(service.id, enabled: $0) }))
          } else if !model.integrationIsEnabled(service.id) {
            Button("Ask AIで有効にする") { model.setIntegrationEnabled(service.id, enabled: true) }
          }
          DisclosureGroup("アクセスと利用設定") {
            VStack(alignment: .leading, spacing: 12) {
              Text(service.permissions)
              if let reason = state.reason { Text(reason).foregroundStyle(.secondary) }
            }.font(.subheadline).padding(.top, 12)
          }
        }
      }
      .padding(20).padding(.vertical, 16)
      .frame(maxWidth: MemoraSpacing.readingWidth)
      .frame(maxWidth: .infinity)
    }
    .onAppear { connected = model.integrationHasConnection(service.id) }
    .onChange(of: scenePhase) { _, phase in if phase == .active { connected = model.integrationHasConnection(service.id) } }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle(service.name)
    .navigationBarTitleDisplayMode(.inline)
    .alert("アクセスを許可できませんでした", isPresented: $permissionFailure) {
      Button("閉じる", role: .cancel) {}
    } message: { Text("設定アプリでカレンダーへのアクセスを確認してください。") }
  }

  @ViewBuilder private func connectionAction(ready: Bool) -> some View {
    switch service.id {
    case "gmail":
      NavigationLink { GmailSettingsView() } label: { actionLabel(ready ? "接続を管理" : "接続") }
        .buttonStyle(MemoraButtonStyle())
    case "notion":
      NavigationLink { NotionSettingsView() } label: { actionLabel(ready ? "接続を管理" : "接続") }
        .buttonStyle(MemoraButtonStyle())
    case "mcp":
      NavigationLink { MCPServersView() } label: { actionLabel("コネクタを追加・管理") }
        .buttonStyle(MemoraButtonStyle())
    case "calendar":
      if CalendarService.access != .granted {
        Button {
          Task {
            if !(await CalendarService.requestAccess()) { permissionFailure = true }
            connected = model.integrationHasConnection(service.id)
          }
        } label: { actionLabel("接続") }
        .buttonStyle(MemoraButtonStyle())
      }
    default: EmptyView()
    }
  }

  private func actionLabel(_ title: String) -> some View { Text(title).frame(maxWidth: .infinity, minHeight: 22) }
}
