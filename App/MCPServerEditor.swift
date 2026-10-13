import SwiftUI

/// Adds or edits one MCP server, and checks that it answers with its tools.
struct MCPServerEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var server: MCPServerConfig
  @State private var token = ""
  @State private var checkedTools: [MCPTool]?
  @State private var errorMessage: String?
  @State private var isChecking = false

  init(server: MCPServerConfig) {
    _server = State(initialValue: server)
  }

  private var isNew: Bool {
    !model.mcpServers.contains { $0.id == server.id }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("名前（例: Notion）", text: $server.name)
          TextField("https://…/mcp", text: $server.url)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
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
          SecureField(isNew ? "アクセストークン（必要な場合）" : "変更するときだけ入力", text: $token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("Bearerトークンとして送ります。キーチェーンに保存し、画面には再表示しません。")
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
          .disabled(isChecking || server.url.trimmingCharacters(in: .whitespaces).isEmpty)

          if let checkedTools {
            Text(checkedTools.isEmpty ? "接続できましたが、道具がありません。" : "\(checkedTools.count)個の道具が提供されています")
              .font(.subheadline.weight(.medium))
            ForEach(checkedTools.prefix(20)) { tool in
              VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.subheadline)
                Text(tool.isReadOnly ? "読み取り" : "実行前に確認")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          if let errorMessage {
            Label(errorMessage, icon: .exclamationmarkTriangle)
              .foregroundStyle(.secondary)
          }
        }
      }
      .disabled(isChecking)
      .onChange(of: server.url) { _, _ in checkedTools = nil; server.approvedReadToolFingerprints = nil }
      .onChange(of: token) { _, _ in checkedTools = nil; server.approvedReadToolFingerprints = nil }
      .navigationTitle(isNew ? "接続先を追加" : "接続先を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            save()
            dismiss()
          }
          .disabled(!isValid || isChecking)
        }
      }
    }
  }

  private var isValid: Bool {
    (try? MCPConnectionPolicy.endpoint(server.url)) != nil
  }

  private func save() {
    server.url = (try? MCPConnectionPolicy.endpoint(server.url).absoluteString) ?? server.url.trimmingCharacters(in: .whitespacesAndNewlines)
    if server.name.trimmingCharacters(in: .whitespaces).isEmpty {
      server.name = URL(string: server.url)?.host ?? "MCP"
    }
    model.saveMCPServer(server, token: token.isEmpty ? nil : token)
  }

  /// Saves first, so the check uses exactly what is entered.
  private func check() {
    guard isValid else {
      errorMessage = MCPClientError.invalidURL.localizedDescription
      return
    }
    server.approvedReadToolFingerprints = nil
    save()
    token = ""
    isChecking = true
    errorMessage = nil
    checkedTools = nil
    let snapshot = server
    Task {
      do {
        let tools = try await model.checkMCPServer(snapshot)
        let endpoint = try MCPConnectionPolicy.endpoint(snapshot.url).absoluteString
        guard (try? MCPConnectionPolicy.endpoint(server.url).absoluteString) == endpoint else {
          isChecking = false
          return
        }
        server.url = endpoint
        checkedTools = tools
        server.reviewedEndpoint = endpoint
        model.saveMCPServer(server, token: nil)
      } catch {
        errorMessage = error.localizedDescription
      }
      isChecking = false
    }
  }
}
