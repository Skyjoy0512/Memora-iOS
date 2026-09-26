import SwiftUI
import UIKit

struct AddTaskView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  /// Set when the task is added from a meeting's "next actions".
  var meetingID: UUID?
  @State private var title = ""
  @State private var assignee = ""
  @State private var includesDueDate = false
  @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
  @State private var remindsAtDue = false
  @State private var reminderDenied = false

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
            Toggle("期限に通知", isOn: reminderBinding)
            if reminderDenied {
              Text("通知が許可されていません。設定から通知を許可してください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
              Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                  openURL(url)
                }
              }
            }
          }
        } footer: {
          Text("通知は期限日の9:00に届きます。")
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
              dueDate: includesDueDate ? dueDate : nil,
              meetingID: meetingID,
              remindsAtDue: includesDueDate && remindsAtDue
            )
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .onChange(of: includesDueDate) { _, isOn in
        if !isOn { remindsAtDue = false }
      }
    }
  }

  /// Asks for notification permission the first time a reminder is turned on.
  private var reminderBinding: Binding<Bool> {
    Binding {
      remindsAtDue
    } set: { enabled in
      guard enabled else {
        remindsAtDue = false
        return
      }
      Task {
        if await TaskReminderScheduler.requestAuthorization() {
          remindsAtDue = true
          reminderDenied = false
        } else {
          remindsAtDue = false
          reminderDenied = true
        }
      }
    }
  }
}
