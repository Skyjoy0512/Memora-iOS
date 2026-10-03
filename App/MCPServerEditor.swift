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
        } footer: {
          Text("Streamable HTTPのMCPサーバーのURLを入力します。")
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
            Text(checkedTools.isEmpty ? "接続できましたが、道具がありません。" : "\(checkedTools.count)個の道具が使えます")
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
          .disabled(!isValid)
        }
      }
    }
  }

  private var isValid: Bool {
    guard let url = URL(string: server.url.trimmingCharacters(in: .whitespaces)) else { return false }
    return url.scheme?.lowercased() == "https" && url.host != nil
  }

  private func save() {
    server.url = server.url.trimmingCharacters(in: .whitespacesAndNewlines)
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
    save()
    isChecking = true
    errorMessage = nil
    checkedTools = nil
    Task {
      do {
        checkedTools = try await model.checkMCPServer(server)
      } catch {
        errorMessage = error.localizedDescription
      }
      isChecking = false
    }
  }
}
