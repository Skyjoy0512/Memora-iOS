import SwiftUI

/// Adds or edits one webhook. The URL is only shown while it is being typed;
/// once saved it stays in the keychain.
struct WebhookEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var endpoint: WebhookEndpoint
  @State private var url = ""
  @State private var errorMessage: String?

  init(endpoint: WebhookEndpoint) {
    _endpoint = State(initialValue: endpoint)
  }

  private var isNew: Bool {
    !model.webhookEndpoints.contains { $0.id == endpoint.id }
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("名前（例: 営業チームのSlack）", text: $endpoint.name)
          Picker("形式", selection: $endpoint.format) {
            ForEach(WebhookEndpoint.Format.allCases) { format in
              Text(format.label).tag(format)
            }
          }
          Toggle("要約ができたら送る", isOn: $endpoint.isEnabled)
        }

        Section {
          TextField(isNew ? "https://hooks.example.com/…" : "変更するときだけ入力", text: $url)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        } header: {
          Text("URL")
        } footer: {
          Text(isNew ? "送り先のサービスで発行したWebhook URLを貼り付けます。" : "保存済みのURLは表示しません。")
        }

        if !isNew {
          Section {
            Button("テスト送信", icon: .paperplane) {
              model.testWebhook(endpoint)
            }
            if let result = model.webhookResults[endpoint.id] {
              Text(result.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          } footer: {
            Text("接続確認用のダミーデータだけを送ります。会議の内容やタスクは送信しません。")
          }
        }

        if let errorMessage {
          Section {
            Label(errorMessage, icon: .exclamationmarkTriangle)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(isNew ? "送り先を追加" : "送り先を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(isNew && url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }

  private func save() {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      guard let parsed = URL(string: trimmed), parsed.scheme?.lowercased() == "https", parsed.host != nil else {
        errorMessage = "https から始まるURLを入力してください。"
        return
      }
    }
    if endpoint.name.trimmingCharacters(in: .whitespaces).isEmpty {
      endpoint.name = endpoint.format == .slack ? "Slack" : "Webhook"
    }
    guard model.saveWebhook(endpoint, url: trimmed.isEmpty ? nil : trimmed) else {
      errorMessage = "URLを保存できませんでした。"
      return
    }
    dismiss()
  }
}
