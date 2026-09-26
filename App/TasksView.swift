import SwiftUI

struct TasksView: View {
  @Environment(MemoraModel.self) private var model
  @State private var showsCompleted = false
  @State private var path: [UUID] = []
  @State private var editingTask: MemoraTask?
  /// nil = everyone, "" = no assignee, otherwise the name.
  @State private var assigneeFilter: String?

  var body: some View {
    @Bindable var model = model

    return NavigationStack(path: $path) {
      VStack(spacing: 0) {
        Picker("表示するタスク", selection: $showsCompleted) {
          Text("未完了").tag(false)
          Text("完了").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)

        if model.isRecording {
          ActiveRecordingStrip()
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }

        if visibleTasks.isEmpty {
          ContentUnavailableView {
            Label(showsCompleted ? "完了したタスクはありません" : "タスクはありません", systemImage: "checkmark.square")
          } description: {
            Text(showsCompleted ? "完了にしたタスクがここに残ります。" : "会話から次の行動が見つかると、自動でここに集まります。")
          }
          .frame(maxHeight: .infinity)
        } else {
          List {
            if showsCompleted {
              ForEach(completedTasks) { task in
                taskRow(task)
              }
            } else {
              ForEach(dueSections) { section in
                Section(section.title) {
                  ForEach(section.tasks) { task in
                    taskRow(task)
                  }
                }
              }
            }
          }
          .hideBottomBarOnScroll(RootTab.tasks.rawValue)
          .listStyle(.plain)
          .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
          .refreshable { await model.refresh() }
        }
      }
      .navigationTitle("タスク")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Picker("担当", selection: $assigneeFilter) {
              Text("全員").tag(String?.none)
              Text("担当なし").tag(String?.some(""))
              ForEach(assigneeNames, id: \.self) { name in
                Text(name).tag(String?.some(name))
              }
            }
          } label: {
            Label("担当で絞り込み", systemImage: "line.3.horizontal.decrease")
              .labelStyle(.iconOnly)
          }
        }

        // The create action is the rightmost item, matching the other tabs.
        ToolbarItem(placement: .primaryAction) {
          Button("タスクを追加", systemImage: "text.badge.plus") {
            model.isAddTaskPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .navigationDestination(for: UUID.self) { meetingID in
        MeetingDetailView(meetingID: meetingID)
      }
      .sheet(isPresented: $model.isAddTaskPresented) {
        AddTaskView()
      }
      .sheet(item: $editingTask) { task in
        TaskEditView(task: task)
      }
      .onAppear { openPendingTaskIfNeeded() }
      .onChange(of: model.pendingTaskEditID) { _, _ in openPendingTaskIfNeeded() }
    }
  }

  private func taskRow(_ task: MemoraTask) -> some View {
    HStack(alignment: .top, spacing: 8) {
      TaskRow(task: task, showsSource: true) {
        editingTask = task
      }

      if let meetingID = task.meetingID {
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
    .swipeActions(edge: .leading) {
      Button {
        model.toggleTask(task.id)
      } label: {
        Label(
          task.isCompleted ? "未完了に戻す" : "完了",
          systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
        )
      }
      .tint(.blue)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        model.deleteTask(task.id)
      } label: {
        Label("削除", systemImage: "trash")
      }
    }
    .contextMenu {
      Button("編集", systemImage: "pencil") { editingTask = task }
      Button("期限を今日に", systemImage: "sun.max") { model.setTaskDueDate(task.id, to: .now) }
      Button("期限を明日に", systemImage: "sunrise") {
        model.setTaskDueDate(task.id, to: Calendar.current.date(byAdding: .day, value: 1, to: .now))
      }
      Button("期限を来週に", systemImage: "calendar") {
        model.setTaskDueDate(task.id, to: Calendar.current.date(byAdding: .day, value: 7, to: .now))
      }
      if let meetingID = task.meetingID {
        Button("元の会議を開く", systemImage: "doc.text") { path.append(meetingID) }
      }
      Button("削除", systemImage: "trash", role: .destructive) { model.deleteTask(task.id) }
    }
  }

  private func openPendingTaskIfNeeded() {
    guard let id = model.pendingTaskEditID, let task = model.tasks.first(where: { $0.id == id }) else { return }
    model.pendingTaskEditID = nil
    showsCompleted = task.isCompleted
    editingTask = task
  }

  private var visibleTasks: [MemoraTask] {
    model.tasks.filter { $0.isCompleted == showsCompleted && matchesAssignee($0) }
  }

  private var completedTasks: [MemoraTask] {
    visibleTasks.sorted { lhs, rhs in
      switch (lhs.completedAt, rhs.completedAt) {
      case let (l?, r?): l > r
      case (nil, _?): false
      case (_?, nil): true
      case (nil, nil): false
      }
    }
  }

  /// Incomplete tasks grouped by when they are due, in the order the sections
  /// should read. An empty section is left out.
  private var dueSections: [TaskDueSection] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today

    let ordered = visibleTasks.sorted {
      ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
    }
    var sections: [TaskDueSection] = []
    for task in ordered {
      let bucket = dueBucket(task, today: today, tomorrow: tomorrow, weekEnd: weekEnd, calendar: calendar)
      if let index = sections.firstIndex(where: { $0.id == bucket.id }) {
        sections[index].tasks.append(task)
      } else {
        sections.append(TaskDueSection(id: bucket.id, title: bucket.title, tasks: [task]))
      }
    }
    // A fixed order, so 期限切れ stays on top even when sorting hid it.
    let order = ["overdue", "today", "tomorrow", "week", "later", "none"]
    return sections.sorted {
      (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count)
    }
  }

  private func dueBucket(
    _ task: MemoraTask,
    today: Date,
    tomorrow: Date,
    weekEnd: Date,
    calendar: Calendar
  ) -> (id: String, title: String) {
    guard let due = task.dueDate else { return ("none", "期限なし") }
    let day = calendar.startOfDay(for: due)
    if day < today { return ("overdue", "期限切れ") }
    if day == today { return ("today", "今日") }
    if day == tomorrow { return ("tomorrow", "明日") }
    if day < weekEnd { return ("week", "今週") }
    return ("later", "それ以降")
  }

  private var assigneeNames: [String] {
    let names = model.tasks.compactMap(\.assignee).filter { !$0.isEmpty }
    return Array(Set(names)).sorted()
  }

  private func matchesAssignee(_ task: MemoraTask) -> Bool {
    switch assigneeFilter {
    case nil:
      true
    case .some(""):
      (task.assignee ?? "").isEmpty
    case .some(let name):
      task.assignee == name
    }
  }
}

/// A due-date heading and the tasks under it, for the tasks list.
private struct TaskDueSection: Identifiable {
  var id: String
  var title: String
  var tasks: [MemoraTask]
}
