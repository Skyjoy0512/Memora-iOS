import SwiftUI

/// Adds or edits one MCP server, and checks that it answers with its tools.
struct MCPServerEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var server: MCPServerConfig
  @State private var token = ""
  @State private var checkedTools: [MCPTool]?
  @State private var inventoryIsPartial = false
  @State private var errorMessage: String?
  @State private var isChecking = false
  @State private var checkingTask: Task<Void, Never>?
  @State private var authorizationTask: Task<Void, Never>?
  @State private var browser = MCPOAuthBrowser()

  init(server: MCPServerConfig) {
    _server = State(initialValue: server)
  }

  private var isNew: Bool {
    !model.mcpServers.contains { $0.id == server.id }
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("名前（例: Notion）", text: $server.name)
          if let preset = server.validatedPreset {
            LabeledContent("アクセス", value: "読み取り専用")
            Text(preset.tokenGuidance).font(.subheadline).foregroundStyle(.secondary)
          } else {
            TextField("https://…/mcp", text: $server.url)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
          }
          Toggle("エージェントで使う", isOn: $server.isEnabled)
        }
        .disabled(isChecking)

        Section {
          Toggle("料金が発生する、または料金が不明", isOn: Binding(get: { server.hasUsageCharges ?? true }, set: { server.hasUsageCharges = $0 }))
          Toggle("確認した読み取りツールを自動許可", isOn: Binding(
            get: { !(server.approvedReadToolFingerprints ?? [:]).isEmpty },
            set: { enabled in server.approvedReadToolFingerprints = enabled ? Dictionary((checkedTools ?? []).filter(\.isReadOnly).map { ($0.name, $0.fingerprint) }, uniquingKeysWith: { first, _ in first }) : nil }))
            .disabled((checkedTools == nil || server.hasUsageCharges != false) && (server.approvedReadToolFingerprints ?? [:]).isEmpty)
        } footer: {
          Text("接続確認後にツールを確認してください。サーバーの読み取り申告だけでは自動許可しません。料金・変更・削除・端末の記録を外部へ渡す操作は実行前に確認します。")
        }

        Section {
          if server.preset == nil {
            Toggle("ブラウザーでサインイン（OAuth）", isOn: Binding(
              get: { server.oauth != nil },
              set: { server.oauth = $0 ? MCPOAuthSettings() : nil; token = "" }))
          }
          if server.oauth != nil {
            TextField("公開Client ID", text: oauthBinding(\.clientID))
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("認可URL（https://…）", text: oauthBinding(\.authorizationURL))
              .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("トークンURL（https://…）", text: oauthBinding(\.tokenURL))
              .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("要求する権限（スペース区切り）", text: oauthBinding(\.scopes))
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            LabeledContent("戻り先", value: MCPOAuthPolicy.redirectURI.absoluteString)
              .font(.footnote).textSelection(.enabled)
            Text(model.hasMCPOAuthCredential(server) ? "認証情報あり・接続確認は別途必要です" : "未認証")
              .font(.footnote).foregroundStyle(.secondary)
            Button("サインイン") { authorize() }
              .disabled(!isValid || isChecking)
            if model.hasMCPOAuthCredential(server) {
              Button("この端末から接続を解除", role: .destructive) {
                do {
                  try model.disconnectMCPOAuth(server.id)
                  server.reviewedEndpoint = nil; server.approvedReadToolFingerprints = nil
                  checkedTools = nil
                } catch { errorMessage = error.localizedDescription }
              }
            }
          } else {
            SecureField(isNew ? (server.preset == nil ? "アクセストークン（必要な場合）" : "アクセストークン") : "変更するときだけ入力", text: $token)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .accessibilityIdentifier("connector.token")
          }
        } footer: {
          Text(server.oauth == nil ? "Bearerトークンはキーチェーンに保存し、画面には再表示しません。" : "認可・トークンURLは同じホストの公開クライアント・PKCE対応の認証先に限定します。戻り先を事前登録してください。Client Secretは入力しません。権限と認証先を確認した後だけサインインします。解除は端末内の認証情報を削除します。サーバー側の許可取消はサービスの設定で行ってください。")
        }

        Section {
          Button {
            check()
          } label: {
            HStack {
              Label("接続を確認", icon: .plugsConnected)
              Spacer()
              if isChecking { ProgressView() }
            }
          }
          .disabled(isChecking || !isValid)
          .accessibilityIdentifier("connector.check")

          if let checkedTools {
            Text(checkedTools.isEmpty ? "接続できましたが、利用できるツールがありません。" : "読み込んだツール \(checkedTools.count)件\(inventoryIsPartial ? "（一部）" : "")")
              .font(.subheadline.weight(.medium))
            if inventoryIsPartial {
              Text("件数・ページ数・形式の上限により一部を読み込んでいます。サーバーの全ツール数ではありません。")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("connector.partialInventory")
            }
            ForEach(checkedTools) { tool in
              VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.subheadline)
                Text(tool.isReadOnly ? "読み取り" : "実行前に確認")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Text("1接続先から最大40ツール・4ページを確認し、1回の回答には最大4接続先・16ツールを選びます。")
            .font(.footnote).foregroundStyle(.secondary)
          if let errorMessage {
            Label(errorMessage, icon: .exclamationmarkTriangle)
              .foregroundStyle(.secondary)
          }
        }
      }
      .disabled(isChecking)
      .onChange(of: server.url) { _, _ in checkedTools = nil; server.approvedReadToolFingerprints = nil }
      .onDisappear { authorizationTask?.cancel(); checkingTask?.cancel(); browser.cancel() }
      .onChange(of: server.oauth) { _, _ in checkedTools = nil; server.reviewedEndpoint = nil; server.approvedReadToolFingerprints = nil }
      .onChange(of: token) { _, _ in checkedTools = nil; server.approvedReadToolFingerprints = nil }
      .navigationTitle(server.validatedPreset?.name ?? (isNew ? "接続先を追加" : "接続先を編集"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            if save() { dismiss() }
          }
          .disabled(!isValid || isChecking)
        }
      }
    }
  }

  private var isValid: Bool {
    (try? MCPConnectionPolicy.endpoint(server.url)) != nil && (server.oauth == nil || (try? MCPOAuthPolicy.validated(server.oauth!)) != nil)
      && (server.preset == nil || (!token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || KeychainStore.has(server.tokenAccount)))
  }

  @discardableResult
  private func save() -> Bool {
    server.url = (try? MCPConnectionPolicy.endpoint(server.url).absoluteString) ?? server.url.trimmingCharacters(in: .whitespacesAndNewlines)
    if server.name.trimmingCharacters(in: .whitespaces).isEmpty {
      server.name = URL(string: server.url)?.host ?? "MCP"
    }
    guard model.saveMCPServer(server, token: server.oauth == nil && !token.isEmpty ? token : nil),
          let saved = model.mcpServers.first(where: { $0.id == server.id }) else {
      errorMessage = MCPOAuthError.storage.localizedDescription
      return false
    }
    server = saved
    return true
  }

  private func oauthBinding(_ key: WritableKeyPath<MCPOAuthSettings, String>) -> Binding<String> {
    Binding(get: { server.oauth?[keyPath: key] ?? "" }, set: { value in
      var settings = server.oauth ?? MCPOAuthSettings()
      settings[keyPath: key] = value
      server.oauth = settings
    })
  }

  private func authorize() {
    guard isValid, save() else { return }
    checkedTools = nil; errorMessage = nil; isChecking = true
    let snapshot = server
    authorizationTask = Task {
      defer { isChecking = false }
      do {
        try await model.authorizeMCPServer(snapshot, browser: browser)
        if let saved = model.mcpServers.first(where: { $0.id == snapshot.id }) { server = saved }
      } catch {
        if !(error is CancellationError) {
          errorMessage = (error as? MCPOAuthError)?.localizedDescription ?? (error as? MCPClientError)?.localizedDescription ?? MCPOAuthError.tokenResponse.localizedDescription
        }
      }
    }
  }

  /// Saves first, so the check uses exactly what is entered.
  private func check() {
    guard isValid else {
      errorMessage = MCPClientError.invalidURL.localizedDescription
      return
    }
    server.approvedReadToolFingerprints = nil
    guard save() else { return }
    token = ""
    isChecking = true
    errorMessage = nil
    checkedTools = nil
    let snapshot = server
    let revision = model.mcpCredentialRevisions[server.id]
    checkingTask = Task {
      do {
        let tools = try await model.checkMCPServer(snapshot)
        let partial = await MCPClient.shared.inventoryIsPartial(on: snapshot.id)
        try Task.checkCancellation()
        let endpoint = try MCPConnectionPolicy.endpoint(snapshot.url).absoluteString
        guard revision == model.mcpCredentialRevisions[snapshot.id], model.mcpServers.contains(snapshot),
              (try? MCPConnectionPolicy.endpoint(server.url).absoluteString) == endpoint else {
          isChecking = false
          return
        }
        server.url = endpoint
        checkedTools = tools
        inventoryIsPartial = partial
        server.reviewedEndpoint = endpoint
        model.saveMCPServer(server, token: nil)
      } catch {
        errorMessage = error.localizedDescription
      }
      isChecking = false
    }
  }
}
