import SwiftUI

struct AIMemoryEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var memory: AIMemory
  @State private var text = ""
  @State private var status = AIMemory.Status.current
  @State private var kind = AIMemory.Kind.fact
  @State private var sensitivity = AIMemory.Sensitivity.standard
  @State private var failed = false
  @State private var predicate = "note"

  var body: some View {
    let sources = model.aiHistory.filter { $0.episode?.workspaceID == model.currentTeamID && $0.episode.map { memory.sourceSessionIDs.contains($0.sessionID) } == true }.prefix(5)
    return NavigationStack {
      Form {
        Section {
          TextField("覚えていること", text: $text, axis: .vertical)
          Picker("種類", selection: $kind) { ForEach(AIMemory.Kind.allCases, id: \.self) { Text($0.label).tag($0) } }
          Picker("状態", selection: $status) { ForEach(AIMemory.Status.allCases, id: \.self) { Text($0.label).tag($0) } }
          Picker("機微情報", selection: $sensitivity) { ForEach(AIMemory.Sensitivity.allCases, id: \.self) { Text($0.label).tag($0) } }
          TextField("項目名（例: 役割）", text: $predicate)
        } header: {
          Text("内容")
        } footer: {
          Text("同じ項目名の有効な値が異なるときは「矛盾あり」として保持します。過去・未確認・矛盾・機微情報は自動利用しません。")
        }
        Section("出典") {
          Text(memory.semantic?.sourceReference ?? "以前のバージョンで明示的に保存")
            .font(.caption).textSelection(.enabled)
          ForEach(Array(sources)) { entry in
            NavigationLink("元の会話: " + String(entry.question.prefix(60))) {
              AIHistoryDetailView(entry: entry, ask: { _ = model.sendAIChat($0); dismiss() })
            }
          }
          LabeledContent("最終更新", value: memory.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }
        if let revisions = memory.revisions, !revisions.isEmpty {
          Section("過去の内容") {
            ForEach(Array(revisions.enumerated()), id: \.offset) { _, revision in
              VStack(alignment: .leading, spacing: 4) {
                Text(revision.text)
                Text(revision.supersededAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        Section {
          Button("削除", role: .destructive) { if model.deleteAIMemories([memory.id]) { dismiss() } else { failed = true } }
        }
      }
      .tint(.primary)
      .navigationTitle("記憶を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            if model.updateAIMemory(memory.id, text: text, status: status, kind: kind, sensitivity: sensitivity, predicate: predicate) { dismiss() } else { failed = true }
          }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("保存できませんでした", isPresented: $failed) { Button("閉じる", role: .cancel) {} } message: { Text("記憶は変更していません。保存先を確認して再試行してください。") }
      .onAppear {
        text = memory.text; status = memory.status; kind = memory.semantic?.type ?? .fact
        sensitivity = memory.semantic?.sensitivity ?? .standard; predicate = memory.semantic?.predicate ?? "note"
      }
    }
  }
}
