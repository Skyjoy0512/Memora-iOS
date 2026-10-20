import SwiftUI

struct AIMemoryEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var memory: AIMemory
  @State private var draft: AIMemoryEditDraft
  @State private var failed = false

  init(memory: AIMemory) {
    self.memory = memory
    _draft = State(initialValue: AIMemoryEditDraft(memory: memory))
  }

  var body: some View {
    let canEdit = model.canEditAIMemory(memory)
    let isWorkspaceCurrent = memory.workspaceID == model.currentTeamID
    let related = AIMemoryEditPlan.relatedMemories(in: model.aiMemories, to: memory, predicate: draft.predicate)
    let sources = model.aiHistory.filter { $0.episode?.workspaceID == model.currentTeamID && $0.episode.map { memory.sourceSessionIDs.contains($0.sessionID) } == true }.prefix(5)
    return NavigationStack {
      MemoraForm {
        if !canEdit {
          Section {
            Text("この記憶または保存先の状態が変わりました。閉じてから、現在の記憶を開き直してください。")
          }
        }
        if isWorkspaceCurrent {
          AIMemoryEditFields(draft: $draft, related: related).disabled(!canEdit)
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
                  Text("\(revision.semantic?.status.label ?? AIMemory.Status.current.label) · \(revision.supersededAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
          Section {
            Button("削除", role: .destructive) { if model.deleteAIMemory(memory) { dismiss() } else { failed = true } }
              .disabled(!canEdit)
          }
        }
      }
      .tint(.primary)
      .navigationTitle("記憶を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            if model.saveAIMemoryEdit(draft.plan(for: memory, related: related)) { dismiss() } else { failed = true }
          }
          .disabled(!canEdit || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.text.count > 200)
        }
      }
      .alert("保存できませんでした", isPresented: $failed) { Button("閉じる", role: .cancel) {} } message: { Text("今回の編集は保存していません。記憶や保存先の状態が変わった可能性があります。内容を確認して開き直してください。") }
      .onChange(of: model.currentTeamID) { dismiss() }
    }
  }
}
