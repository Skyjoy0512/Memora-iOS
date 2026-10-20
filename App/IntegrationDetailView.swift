import SwiftUI

struct IntegrationDetailView: View {
  @Environment(MemoraModel.self) private var model
  var service: IntegrationCatalog

  var body: some View {
    let state = model.integrationState(service)
    ScrollView {
      VStack(alignment: .leading, spacing: MemoraSpacing.section) {
        IntegrationArticleHeader(service: service, status: state.label)
        Text(service.summary).memoraReadingText()
        if let reason = state.reason {
          Text(reason).font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
            .lineSpacing(4)
        }
        VStack(alignment: .leading, spacing: MemoraSpacing.md) {
          Text("アクセスと料金").font(MemoraTypography.sectionHeading)
          Text(service.permissions).memoraReadingText()
          Text(service.id == "calendar" ? "料金：端末内の操作" : "料金：外部サービスの料金を確認・実行前に承認")
            .font(.subheadline).foregroundStyle(MemoraPalette.textSecondary).lineSpacing(4)
        }
        DisclosureGroup("利用できる操作") {
          VStack(alignment: .leading, spacing: MemoraSpacing.md) {
            ForEach(service.toolNames, id: \.self) { name in
              if let tool = AgentTool(rawValue: name) { Text(tool.summary).font(.subheadline).lineSpacing(4) }
            }
            if service.id == "mcp" { Text("各サーバーの設定で、確認済みのツールと権限を確認できます。") }
          }
          .padding(.top, MemoraSpacing.md)
        }
        .frame(minHeight: MemoraSpacing.touchTarget)
        if service.isImplemented {
          IntegrationArticleControls(service: service)
        } else {
          VStack(alignment: .leading, spacing: MemoraSpacing.md) {
            Text("現在は接続できません。")
            Text("Composioの管理キーはアプリに保存しません。ユーザー認証・料金上限を管理するサーバーの接続後に提供します。")
              .font(.footnote).foregroundStyle(MemoraPalette.textSecondary).lineSpacing(4)
          }
        }
      }
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .padding(.horizontal, MemoraSpacing.screen)
      .padding(.vertical, MemoraSpacing.xxl)
      .frame(maxWidth: .infinity, alignment: .center)
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
      Toggle("Ask AIで利用する", isOn: Binding(
        get: { model.integrationIsEnabled(service.id) },
        set: { model.setIntegrationEnabled(service.id, enabled: $0) }))
        .frame(minHeight: 44)
      Divider()
      switch service.id {
      case "gmail":
        NavigationLink { GmailSettingsView() } label: { IntegrationSetupLabel(title: "接続・認証設定") }
      case "notion":
        NavigationLink { NotionSettingsView() } label: { IntegrationSetupLabel(title: "接続・認証設定") }
      case "mcp":
        NavigationLink { MCPServersView() } label: { IntegrationSetupLabel(title: "接続先を管理") }
      case "calendar":
        if CalendarService.access != .granted {
          Button("カレンダーへのアクセスを許可") { Task { _ = await CalendarService.requestAccess() } }
            .buttonStyle(MemoraButtonStyle())
        }
      default: EmptyView()
      }
      Text("無効にしても認証情報は削除しません。接続解除は各サービスの設定から行えます。")
        .font(.footnote).foregroundStyle(MemoraPalette.textSecondary).lineSpacing(4)
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
