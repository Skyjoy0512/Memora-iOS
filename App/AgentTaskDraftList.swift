import SwiftUI

struct AgentTaskDraftList: View {
  var drafts: [AgentTaskDraft]
  var update: (AgentTaskDraft) -> Void
  @State private var editingDraft: AgentTaskDraft?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(drafts) { draft in
        HStack(alignment: .top, spacing: 4) {
          Toggle(isOn: Binding(get: { draft.isSelected }, set: { selected in
            var edited = draft; edited.isSelected = selected; update(edited)
          })) {
            HStack(alignment: .top, spacing: 10) {
              Image(icon: draft.isSelected ? .checkmarkCircleFill : .circle)
              VStack(alignment: .leading, spacing: 5) {
                Text(draft.title).font(.body).fixedSize(horizontal: false, vertical: true)
                if !draft.detail.isEmpty {
                  Text(draft.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                let metadata = [draft.assignee.isEmpty ? nil : draft.assignee,
                  draft.dueDate?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }
                if !metadata.isEmpty {
                  Text(metadata.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
              Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .toggleStyle(.button).buttonStyle(.plain)
          .accessibilityLabel(draft.title)
          .accessibilityHint("選択した候補だけを登録します")
          Button("編集", icon: .pencil) { editingDraft = draft }
            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("\(draft.title)を編集")
        }
      }
    }
    .foregroundStyle(.primary)
    .tint(MemoraPalette.textPrimary)
    .sheet(item: $editingDraft) { draft in AgentTaskDraftEditor(draft: draft, save: update) }
  }
}
