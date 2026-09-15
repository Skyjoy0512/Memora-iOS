import SwiftUI

struct TasksView: View {
  @Environment(MemoraModel.self) private var model
  @State private var showsCompleted = false
  @State private var path: [UUID] = []
  @State private var isAddingTask = false

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        Picker("表示するタスク", selection: $showsCompleted) {
          Text("未完了").tag(false)
          Text("完了").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)

        if visibleTasks.isEmpty {
          ContentUnavailableView {
            Label(showsCompleted ? "完了したタスクはありません" : "タスクはありません", systemImage: "checkmark.square")
          } description: {
            Text(showsCompleted ? "完了にしたタスクがここに残ります。" : "会話から次の行動が見つかると、自動でここに集まります。")
          }
          .frame(maxHeight: .infinity)
        } else {
          List {
            ForEach(visibleTasks) { task in
              HStack(alignment: .top, spacing: 8) {
                TaskRow(task: task, showsSource: true)

                if let meetingID = task.meetingID {
                  // A Button rather than a NavigationLink so List does not add
                  // a second disclosure indicator next to this one.
                  Button("元の会議を開く", systemImage: "chevron.right") {
                    path.append(meetingID)
                  }
                  .labelStyle(.iconOnly)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
                  .frame(width: 32, height: 44)
                  .buttonStyle(.plain)
                }
              }
              .padding(.vertical, 5)
            }
          }
          .hideBottomBarOnScroll()
          .listStyle(.plain)
        }
      }
      .navigationTitle("タスク")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("新規タスク", systemImage: "plus") {
            isAddingTask = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .navigationDestination(for: UUID.self) { meetingID in
        MeetingDetailView(meetingID: meetingID)
      }
      .sheet(isPresented: $isAddingTask) {
        AddTaskView()
      }
    }
  }

  private var visibleTasks: [MemoraTask] {
    model.tasks
      .filter { $0.isCompleted == showsCompleted }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }
}

private struct AddTaskView: View {
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
