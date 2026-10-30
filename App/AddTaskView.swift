import SwiftUI
import UIKit

struct AddTaskView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var cancelsEditing = false
  @State private var editorCompleted = false
  @Environment(\.openURL) private var openURL
  /// Set when the task is added from a meeting's "next actions".
  var meetingID: UUID?
  var parentTaskID: UUID?
  @State private var title = ""
  @State private var assignee = ""
  @State private var assigneePersonID: UUID?
  @State private var saveError = false
  @State private var ownedByMe = true
  @State private var detail = ""
  @State private var includesDueDate = false
  @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
  @State private var remindsAtDue = false
  @State private var reminderTime = TaskReminderScheduler.defaultTimeToday()
  @State private var reminderDenied = false

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section("タスク") {
          TextField("すること", text: $title)
            .accessibilityLabel("すること")
          TaskAssigneeFields(people: model.people, name: $assignee, personID: $assigneePersonID, ownedByMe: $ownedByMe)
          TextField("メモ・完了条件", text: $detail, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityLabel("メモ・完了条件")
        }

        Section {
          Toggle("期限を設定", isOn: $includesDueDate)
          if includesDueDate {
            DatePicker("期限", selection: $dueDate, displayedComponents: .date)
            Toggle("期限に通知", isOn: reminderBinding)
            if remindsAtDue {
              DatePicker("通知の時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
              if isReminderTimePassed {
                Text("この時刻は過ぎているため通知されません。")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
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
          Text("通知は期限日の選んだ時刻に届きます。")
        }
      }
      .navigationTitle("新規タスク")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { cancelsEditing = true }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("追加", icon: .plus) {
            let saved = model.addTask(
              title: title,
              assignee: ownedByMe ? "" : assignee,
              dueDate: includesDueDate ? dueDate : nil,
              meetingID: meetingID,
              remindsAtDue: includesDueDate && remindsAtDue,
              reminderTime: includesDueDate && remindsAtDue ? reminderTime : nil,
              ownedByMe: ownedByMe,
              parentID: parentTaskID,
              detail: detail,
              assigneePersonID: ownedByMe ? nil : assigneePersonID
            )
            if saved { editorCompleted = true; dismiss() } else { saveError = true }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("人物や親課題、保存先の状態を確認してください。入力内容は画面に残っています。")
      }
      .onChange(of: includesDueDate) { _, isOn in
        if !isOn { remindsAtDue = false }
      }
    }
    .protectsEditorDraft(key: "editor.\(model.currentTeamID ?? "personal").task.new.\(meetingID?.uuidString ?? "global").\(parentTaskID?.uuidString ?? "root")",
      fields: [
        EditorDraftField("title", $title),
        EditorDraftField("assignee", $assignee),
        EditorDraftField("person", $assigneePersonID),
        EditorDraftField("owned", $ownedByMe),
        EditorDraftField("detail", $detail),
        EditorDraftField("dueEnabled", $includesDueDate),
        EditorDraftField("due", optionalDate($dueDate, enabled: includesDueDate)),
        EditorDraftField("reminds", $remindsAtDue),
        EditorDraftField("reminder", optionalDate($reminderTime, enabled: includesDueDate && remindsAtDue))
      ], cancels: $cancelsEditing, completed: editorCompleted)
  }

  /// True when the chosen time has already passed on the due day, so nothing
  /// would be scheduled.
  private var isReminderTimePassed: Bool {
    guard includesDueDate, remindsAtDue,
          let components = TaskReminderScheduler.fireComponents(dueDate: dueDate, reminderTime: reminderTime),
          let fireDate = Calendar.current.date(from: components) else { return false }
    return fireDate <= .now
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
