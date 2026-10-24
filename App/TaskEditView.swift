import SwiftUI
import UIKit

/// Edits one task: its title, who owns it, when it is due, and which record it
/// came from. Tasks can also be removed here.
struct TaskEditView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  var task: MemoraTask

  @State private var title: String
  @State private var detail: String
  @State private var hasWorkDate: Bool
  @State private var workDate: Date
  @State private var progress: TaskProgress
  @State private var assignee: String
  @State private var assigneePersonID: UUID?
  @State private var hasDueDate: Bool
  @State private var dueDate: Date
  @State private var meetingID: UUID?
  @State private var remindsAtDue: Bool
  @State private var reminderTime: Date
  @State private var reminderDenied = false
  @State private var isDeleting = false
  @State private var ownedByMe = false
  @State private var parentID: UUID?
  @State private var documentIDs: [UUID]
  @State private var isAddingChild = false
  @State private var editingChild: MemoraTask?
  @State private var isPickingDocuments = false
  @State private var openedDocument: MemoraDocument?
  @State private var saveError = false
  @State private var hasLoadedOwnership = false
  @State private var isPrivacyPresented = false

  init(task: MemoraTask) {
    self.task = task
    _title = State(initialValue: task.title)
    _detail = State(initialValue: task.detail)
    _hasWorkDate = State(initialValue: task.workDate != nil)
    _workDate = State(initialValue: task.workDate ?? .now)
    _progress = State(initialValue: task.progress)
    _assignee = State(initialValue: task.assignee ?? "")
    _assigneePersonID = State(initialValue: task.relationships.assigneePersonID)
    _hasDueDate = State(initialValue: task.dueDate != nil)
    _dueDate = State(initialValue: task.dueDate ?? Date.now.addingTimeInterval(86_400))
    _meetingID = State(initialValue: task.meetingID)
    _remindsAtDue = State(initialValue: task.remindsAtDue)
    _reminderTime = State(initialValue: task.reminderTime ?? TaskReminderScheduler.defaultTimeToday())
    _parentID = State(initialValue: task.relationships.parentID)
    _documentIDs = State(initialValue: task.relationships.documentIDs)
  }

  var body: some View {
    let currentTask = model.tasks.first { $0.id == task.id } ?? task
    let parents = TaskHierarchy.eligibleParents(for: task.id, in: model.tasks)
    let children = model.tasks.filter { $0.relationships.parentID == task.id }
    NavigationStack {
      MemoraForm {
        Section("内容") {
          TextField("タイトル", text: $title, axis: .vertical)
            .accessibilityLabel("タイトル")
          TextField("メモ・完了条件", text: $detail, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityLabel("メモ・完了条件")
          TaskAssigneeFields(people: model.people, name: $assignee, personID: $assigneePersonID, ownedByMe: $ownedByMe)
          if currentTask.isCompleted {
            LabeledContent("状態", value: currentTask.statusLabel)
          } else {
            Picker("進み具合", selection: $progress) {
              ForEach(TaskProgress.allCases) { state in
                Text(state.label).tag(state)
              }
            }
          }
        }

        Section {
          Toggle("取り組む日を設定", isOn: $hasWorkDate)
          if hasWorkDate {
            DatePicker("取り組む日", selection: $workDate, displayedComponents: .date)
          }
        } header: {
          Text("取り組む日")
        } footer: {
          Text("自分の作業予定です。約束した期限は変更しません。")
        }

        Section {
          Toggle("期限を設定", isOn: $hasDueDate)
          if hasDueDate {
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
        } header: {
          Text("期限")
        } footer: {
          Text(hasDueDate ? "期限を過ぎた未完了のタスクは期限切れとして表示します。通知は期限日の選んだ時刻に届きます。" : "期限なしのタスクとして扱います。")
        }

        Section("課題の階層") {
          Picker("親課題", selection: $parentID) {
            Text("なし").tag(UUID?.none)
            ForEach(parents) { parent in
              Text(parent.title).tag(UUID?.some(parent.id))
            }
          }
          ForEach(children) { child in
            Button(child.title) { editingChild = child }
          }
          Button("子課題を追加", icon: .plus) { isAddingChild = true }
        }

        Section("資料") {
          ForEach(documentIDs, id: \.self) { identifier in
            let document = model.document(id: identifier)
            Button(document?.displayTitle ?? "削除された資料") { openedDocument = document }
              .disabled(document == nil)
              .swipeActions {
                Button("添付を外す", role: .destructive) { documentIDs.removeAll { $0 == identifier } }
              }
          }
          Button("資料を添付", icon: .paperclip) { isPickingDocuments = true }
        }

        Section {
          Button("プライバシーと外部送信", icon: .lockShield) { isPrivacyPresented = true }
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
          Button("削除", icon: .trash, role: .destructive) {
            isDeleting = true
          }
        }
      }
      .navigationTitle("タスクを編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            let saved = model.updateTask(
              task.id,
              title: title,
              assignee: assignee,
              dueDate: hasDueDate ? dueDate : nil,
              meetingID: meetingID,
              detail: detail,
              workDate: hasWorkDate ? Calendar.current.startOfDay(for: workDate) : nil,
              progress: progress,
              remindsAtDue: hasDueDate && remindsAtDue,
              reminderTime: hasDueDate && remindsAtDue ? reminderTime : nil,
              ownedByMe: ownedByMe,
              relationships: TaskRelationships(parentID: parentID, documentIDs: documentIDs, assigneePersonID: ownedByMe ? nil : assigneePersonID)
            )
            if saved { dismiss() }
            else { saveError = true }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .confirmationDialog("このタスクを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          if model.deleteTask(task.id) { dismiss() }
        }
        Button("キャンセル", role: .cancel) {}
      }
      .onChange(of: hasDueDate) { _, isOn in
        if !isOn { remindsAtDue = false }
      }
      .onAppear {
        guard !hasLoadedOwnership else { return }
        ownedByMe = model.isOwnTask(task)
        hasLoadedOwnership = true
      }
      .sheet(isPresented: $isAddingChild) { AddTaskView(meetingID: meetingID, parentTaskID: task.id) }
      .sheet(isPresented: $isPrivacyPresented) { RecordPrivacySettingsView(target: .task(task.id)) }
      .sheet(item: $editingChild) { child in TaskEditView(task: child) }
      .sheet(isPresented: $isPickingDocuments) { TaskDocumentPicker(selection: $documentIDs) }
      .sheet(item: $openedDocument) { document in
        NavigationStack { DocumentDetailView(documentID: document.id, showsCloseButton: true) }
      }
      .alert("保存できませんでした", isPresented: $saveError) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("人物や親課題、保存先の状態を確認してください。入力内容は画面に残っています。")
      }
    }
    .presentationDetents([.large])
  }

  private var isReminderTimePassed: Bool {
    guard hasDueDate, remindsAtDue,
          let components = TaskReminderScheduler.fireComponents(dueDate: dueDate, reminderTime: reminderTime),
          let fireDate = Calendar.current.date(from: components) else { return false }
    return fireDate <= .now
  }

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
