import SwiftUI

struct MailDraftsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var editing: MailDraft?
  @State private var deleting: MailDraft?
  var body: some View {
    let drafts = model.mailDrafts.filter { $0.workspaceID == model.currentTeamID }
    MemoraList {
      ForEach(drafts) { draft in
        Button { editing = draft } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(draft.subject.isEmpty ? "件名なし" : draft.subject)
              .font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
            Text((draft.recipients.isEmpty ? "宛先未指定" : draft.recipients.joined(separator: ", ")) + " · 下書き")
              .font(MemoraTypography.metadata).foregroundStyle(.secondary).lineLimit(2)
            Text(MemoraFormat.meetingDate(draft.updatedAt))
              .font(MemoraTypography.metadata).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions { Button("削除", icon: .trash, role: .destructive) { deleting = draft } }
      }
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .overlay(alignment: .top) {
      if drafts.isEmpty {
        ScrollView {
          MemoraEmptyState(icon: .envelope, title: "下書きはありません",
            message: "Ask AIへメールの下書きを依頼すると、ここに保存されます。送信は本人がMailで行います。",
            actionTitle: "Ask AIを開く", actionIcon: .sparkles) { model.openSystemDestination(.askAI) }
            .padding(.top, MemoraSpacing.section)
            .padding(.bottom, model.bottomContentClearance)
        }
      }
    }
    .tint(.primary)
    .navigationTitle("メール下書き").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { draft in MailDraftSheet(draft: draft) { editing = nil } }
    .confirmationDialog("下書きを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
      Button("削除", role: .destructive) { if let deleting { _ = model.deleteMailDraft(deleting.id) }; deleting = nil }
    }
  }
}
