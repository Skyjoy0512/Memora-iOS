import SwiftUI

struct AddTaskView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var assignee = ""
  @State private var includesDueDate = false
  @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now

  var body: some View {
    NavigationStack {
      Form {
        Section("タスク") {
          TextField("すること", text: $title)
          TextField("担当（任意）", text: $assignee)
        }

        Section {
          Toggle("期限を設定", isOn: $includesDueDate)
          if includesDueDate {
            DatePicker("期限", selection: $dueDate, displayedComponents: .date)
          }
        }
      }
      .navigationTitle("新規タスク")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("追加") {
            model.addTask(
              title: title,
              assignee: assignee,
              dueDate: includesDueDate ? dueDate : nil
            )
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
