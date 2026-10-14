import SwiftUI

struct AgentTaskDraftEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: AgentTaskDraft
  @State private var hasDueDate: Bool
  @State private var dueDate: Date
  var save: (AgentTaskDraft) -> Void

  init(draft: AgentTaskDraft, save: @escaping (AgentTaskDraft) -> Void) {
    _draft = State(initialValue: draft)
    _hasDueDate = State(initialValue: draft.dueDate != nil)
    _dueDate = State(initialValue: draft.dueDate ?? .now)
    self.save = save
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("タイトル", text: $draft.title)
          VStack(alignment: .leading, spacing: 6) {
            Text("詳細").font(.footnote).foregroundStyle(.secondary)
            TextEditor(text: $draft.detail)
              .frame(minHeight: 100)
              .scrollContentBackground(.hidden)
              .accessibilityLabel("詳細")
          }
          TextField("担当者（未設定でも登録できます）", text: $draft.assignee)
        }
        Section {
          Toggle("期限を設定", isOn: $hasDueDate)
          if hasDueDate { DatePicker("期限", selection: $dueDate, displayedComponents: .date) }
        }
        if !editedDraft.isValid {
          Text("タイトルは1〜500文字、詳細は4,000文字、担当者は120文字以内にしてください。")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .tint(MemoraPalette.textPrimary)
      .navigationTitle("タスク候補を編集").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("候補に反映", icon: .checkmark) { save(editedDraft); dismiss() }
            .disabled(!editedDraft.isValid)
        }
      }
    }
  }

  private var editedDraft: AgentTaskDraft {
    var copy = draft
    copy.dueDate = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
    return copy
  }
}
