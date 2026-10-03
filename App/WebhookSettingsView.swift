import SwiftUI

/// Where finished summaries are sent automatically: Zapier, Make, n8n, Slack
/// or any https URL.
struct WebhookSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: WebhookEndpoint?

  var body: some View {
    List {
      Section {
        if model.webhookEndpoints.isEmpty {
          Text("まだ送り先がありません")
            .foregroundStyle(.secondary)
        }
        ForEach(model.webhookEndpoints) { endpoint in
          Button {
            editing = endpoint
          } label: {
            row(endpoint)
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("削除", icon: .trash, role: .destructive) {
              model.deleteWebhook(endpoint.id)
            }
          }
        }
        Button("送り先を追加", icon: .plus) {
          editing = WebhookEndpoint(id: UUID(), name: "", format: .json)
        }
      } footer: {
        Text("要約ができるたびに、タイトル・要約・決まったこと・タスクを送ります。Zapier・Make・n8nのWebhookや、SlackのIncoming Webhookを使うと、CRMやスプレッドシート、チャットへ自動で届けられます。送り先のURLはキーチェーンに保存します。")
      }
    }
    .navigationTitle("Webhook")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { endpoint in
      WebhookEditor(endpoint: endpoint)
    }
  }

  private func row(_ endpoint: WebhookEndpoint) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(endpoint.name.isEmpty ? "名前なし" : endpoint.name)
          .font(.body.weight(.medium))
          .foregroundStyle(endpoint.isEnabled ? .primary : .secondary)
        Spacer()
        if !endpoint.isEnabled {
          Text("オフ").font(.caption).foregroundStyle(.secondary)
        }
      }
      Text(endpoint.format.label)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let result = model.webhookResults[endpoint.id] {
        Label(result.message, icon: result.succeeded ? .checkmarkCircleFill : .exclamationmarkTriangle)
          .font(.caption)
          .foregroundStyle(result.succeeded ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}
