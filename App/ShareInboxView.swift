import SwiftUI

struct ShareInboxView: View {
  @Environment(MemoraModel.self) private var model
  @State private var projectID: UUID?
  @State private var deleting: UUID?
  var body: some View {
    Form {
      if ShareInboxConfiguration.root == nil {
        Section {
          Text("共有拡張はまだ接続されていません。App Groupsと署名の設定が必要です。")
            .foregroundStyle(.secondary)
        }
      } else {
        if model.currentTeamID != nil { Text("共有からの取り込みは個人ワークスペースで利用できます。") }
        if let failure = model.shareInboxFailure { Text(failure).foregroundStyle(.secondary) }
        if model.isImportingShareInbox { ProgressView("取り込んでいます") }
        if model.shareInboxRequests.isEmpty && model.shareInboxRejectedIDs.isEmpty { Text("未取り込みの共有はありません").foregroundStyle(.secondary) }
        else {
          Picker("取り込み先", selection: $projectID) {
            Text("共有時の保存先").tag(Optional<UUID>.none)
            ForEach(model.spaces) { Text($0.name).tag(Optional($0.id)) }
          }
          ForEach(model.shareInboxRequests) { request in
            Section {
              ForEach(request.items) { item in Text(item.title.isEmpty ? "共有された内容" : item.title).lineLimit(2) }
              Button("取り込みを再試行") { Task { await model.importShareInbox(requestID: request.id, projectID: projectID) } }
              Button("未取り込みの共有を削除", role: .destructive) { deleting = request.id }
            } header: { Text(request.createdAt.formatted(date: .abbreviated, time: .shortened)) }
          }
          .disabled(model.isImportingShareInbox || model.currentTeamID != nil)
        }
        ForEach(model.shareInboxRejectedIDs, id: \.self) { id in
          Section("読み込めない共有") {
            Text("元のアプリから共有し直してください。正常な共有の取り込みは継続します。")
              .foregroundStyle(.secondary)
            Text(id.uuidString).font(.caption).foregroundStyle(.secondary)
            Button("この共有を削除", role: .destructive) { deleting = id }
              .disabled(model.isImportingShareInbox)
          }
        }
      }
    }
    .navigationTitle("共有からの取り込み").navigationBarTitleDisplayMode(.inline)
    .task { await model.refreshShareInbox() }
    .confirmationDialog("未取り込みの共有を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      Button("削除", role: .destructive) { if let id = deleting { Task { await model.discardShareRequest(id) } }; deleting = nil }
    } message: { Text("受信キューだけを削除します。取り込み済みソースと元のアプリのデータは残ります。") }
  }
}
