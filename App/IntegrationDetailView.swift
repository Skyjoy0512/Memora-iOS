import SwiftUI

struct IntegrationDetailView: View {
  @Environment(MemoraModel.self) private var model
  var service: IntegrationCatalog

  var body: some View {
    let state = model.integrationState(service)
    Form {
      Section {
        LabeledContent("状態", value: state.label)
        if let reason = state.reason { Text(reason).foregroundStyle(.secondary) }
        Text(service.summary)
        Text(service.permissions).font(.subheadline).foregroundStyle(.secondary)
        LabeledContent("料金", value: service.id == "calendar" ? "端末内の操作" : "外部サービスの料金を確認・実行前に承認")
        DisclosureGroup("利用できる操作") {
          ForEach(service.toolNames, id: \.self) { name in
            if let tool = AgentTool(rawValue: name) { Text(tool.summary).font(.subheadline) }
          }
          if service.id == "mcp" { Text("各サーバーの設定で、確認済みのツールと権限を確認できます。") }
        }
      }
      if service.isImplemented {
        Section {
          Toggle("Ask AIで利用する", isOn: Binding(
            get: { model.integrationIsEnabled(service.id) },
            set: { model.setIntegrationEnabled(service.id, enabled: $0) }))
          switch service.id {
          case "gmail": NavigationLink("接続・認証設定") { GmailSettingsView() }
          case "notion": NavigationLink("接続・認証設定") { NotionSettingsView() }
          case "mcp": NavigationLink("接続先を管理") { MCPServersView() }
          case "calendar":
            if CalendarService.access != .granted {
              Button("カレンダーへのアクセスを許可") { Task { _ = await CalendarService.requestAccess() } }
            }
          default: EmptyView()
          }
        } footer: {
          Text("無効にしても認証情報は削除しません。接続解除は各サービスの設定から行えます。")
        }
      } else {
        Section {
          Text("現在は接続できません。")
        } footer: {
          Text("Composioの管理キーはアプリに保存しません。ユーザー認証・料金上限を管理するサーバーの接続後に提供します。")
        }
      }
    }
    .navigationTitle(service.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}
