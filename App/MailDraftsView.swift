import SwiftUI

struct MailDraftsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: MailDraft?
  @State private var deleting: MailDraft?
  var body: some View {
    let drafts = model.mailDrafts.filter { $0.workspaceID == model.currentTeamID }
    List {
      ForEach(drafts) { draft in
        Button { editing = draft } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(draft.subject.isEmpty ? "件名なし" : draft.subject).foregroundStyle(.primary)
            Text((draft.recipients.isEmpty ? "宛先未指定" : draft.recipients.joined(separator: ", ")) + " · 下書き")
              .font(.caption).foregroundStyle(.secondary)
            Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions { Button("削除", icon: .trash, role: .destructive) { deleting = draft } }
      }
    }
    .overlay { if drafts.isEmpty { ContentUnavailableView("下書きはありません", icon: .envelope, description: Text("Ask AIへメールの下書きを依頼すると、ここに保存されます。")) } }
    .navigationTitle("メール下書き").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { draft in MailDraftSheet(draft: draft) { editing = nil } }
    .confirmationDialog("下書きを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      Button("削除", role: .destructive) { if let deleting { _ = model.deleteMailDraft(deleting.id) }; deleting = nil }
    }
  }
}
