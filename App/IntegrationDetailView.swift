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
      VStack(alignment: .leading, spacing: MemoraSpacing.section) {
        MarketplaceDetailHero(item: .service(service), subtitle: "コネクタ") { EmptyView() }
        MarketplaceDescription(text: service.summary)
        MarketplaceDetailFacts(fields: [
          ("接続", service.isImplemented ? (connected ? "接続済み" : state.label) : "準備中"),
          ("Ask AI", state.isReady ? "利用可能" : "利用できません"),
          ("アクセス", accessLabel)
        ])

        if service.isImplemented {
          VStack(alignment: .leading, spacing: 16) {
            Text("このコネクタでできること").font(.headline)
            ForEach(service.capabilities, id: \.self) { capability in
              Label(capability, icon: .checkmark).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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
            }.font(.subheadline).padding(.top, 12)
          }
        }
      }
      .padding(.horizontal, MemoraSpacing.screen)
      .padding(.top, MemoraSpacing.xl)
      .padding(.bottom, MemoraSpacing.section)
      .frame(maxWidth: MemoraSpacing.readingWidth)
      .frame(maxWidth: .infinity)
    }
    .onAppear { connected = model.integrationHasConnection(service.id) }
    .onChange(of: scenePhase) { _, phase in if phase == .active { connected = model.integrationHasConnection(service.id) } }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if service.isImplemented {
        MarketplaceDetailFooter {
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            if let reason = state.reason {
              Text(reason).font(MemoraTypography.metadata)
                .foregroundStyle(MemoraPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("connector.requirement")
            }
            connectionAction(ready: connected)
          }
        }
      }
    }
    .background(MemoraPalette.background)
    .tint(MemoraPalette.textPrimary)
    .navigationTitle("コネクタ")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarActionItem(usesSystemBackground: true) {
        ShareLink(item: "\(service.name)\n\(service.summary)") {
          ToolbarActionLabel("コネクタを共有", icon: .squareAndArrowUp)
        }
      }
    }
    .alert("アクセスを許可できませんでした", isPresented: $permissionFailure) {
      Button("閉じる", role: .cancel) {}
    } message: { Text("設定アプリでカレンダーへのアクセスを確認してください。") }
  }

  @ViewBuilder private func connectionAction(ready: Bool) -> some View {
    switch service.id {
    case "gmail":
      NavigationLink { GmailSettingsView() } label: { actionLabel(ready ? "接続を管理" : "接続") }
        .buttonStyle(.plain)
    case "notion":
      NavigationLink { NotionSettingsView() } label: { actionLabel(ready ? "接続を管理" : "接続") }
        .buttonStyle(.plain)
    case "mcp":
      NavigationLink { MCPServersView() } label: { actionLabel("コネクタを追加・管理") }
        .buttonStyle(.plain)
    case "calendar":
      if CalendarService.access != .granted {
        Button {
          Task {
            if !(await CalendarService.requestAccess()) { permissionFailure = true }
            connected = model.integrationHasConnection(service.id)
          }
        } label: { actionLabel("接続") }
        .buttonStyle(.plain)
      } else {
        MarketplaceDetailActionLabel(title: "接続済み", icon: .checkmark)
          .accessibilityLabel("カレンダーは接続済みです")
      }
    default: EmptyView()
    }
  }

  private func actionLabel(_ title: String) -> some View {
    MarketplaceDetailActionLabel(title: title)
  }

  private var accessLabel: String {
    switch service.id {
    case "gmail": "読み取り専用"
    case "calendar": "予定の閲覧・追加"
    case "notion": "ページの作成"
    case "mcp": "接続先に準ずる"
    default: "準備中"
    }
  }
}
