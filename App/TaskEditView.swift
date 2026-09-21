import SwiftUI

/// Edits one task: its title, who owns it, when it is due, and which record it
/// came from. Tasks can also be removed here.
struct TaskEditView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var task: MemoraTask

  @State private var title: String
  @State private var assignee: String
  @State private var hasDueDate: Bool
  @State private var dueDate: Date
  @State private var meetingID: UUID?
  @State private var isDeleting = false

  init(task: MemoraTask) {
    self.task = task
    _title = State(initialValue: task.title)
    _assignee = State(initialValue: task.assignee ?? "")
    _hasDueDate = State(initialValue: task.dueDate != nil)
    _dueDate = State(initialValue: task.dueDate ?? Date.now.addingTimeInterval(86_400))
    _meetingID = State(initialValue: task.meetingID)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("内容") {
          TextField("タイトル", text: $title, axis: .vertical)
          TextField("担当", text: $assignee)
        }

        Section {
          Toggle("期限を設定", isOn: $hasDueDate)
          if hasDueDate {
            DatePicker("期限", selection: $dueDate, displayedComponents: .date)
          }
        } header: {
          Text("期限")
        } footer: {
          Text(hasDueDate ? "期限を過ぎた未完了のタスクは期限切れとして表示します。" : "期限なしのタスクとして扱います。")
        }

        Section("元の会議") {
          Picker("元の会議", selection: $meetingID) {
            Text("なし").tag(UUID?.none)
            ForEach(model.meetings) { meeting in
              Text(meeting.title).tag(UUID?.some(meeting.id))
            }
          }
          .pickerStyle(.menu)
        }

        Section {
          Button("削除", systemImage: "trash", role: .destructive) {
            isDeleting = true
          }
        }
      }
      .navigationTitle("タスクを編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            model.updateTask(
              task.id,
              title: title,
              assignee: assignee,
              dueDate: hasDueDate ? dueDate : nil,
              meetingID: meetingID
            )
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .confirmationDialog("このタスクを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteTask(task.id)
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      }
    }
    .presentationDetents([.medium, .large])
  }
}
