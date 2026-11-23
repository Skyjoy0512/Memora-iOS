import SwiftUI

struct TasksView: View {
  @Environment(MemoraModel.self) private var model
  @State private var showsCompleted = false
  @State private var editingTask: MemoraTask?
  @State private var todayOnly = false
  @State private var waitingOnly = false
  @State private var showsTeamBoard = false

  var body: some View {
    @Bindable var model = model
    let visibleTasks = self.visibleTasks
    let taskDepths = TaskHierarchy.depths(in: visibleTasks)
    let isFiltered = todayOnly || waitingOnly

    return Group {
      if showsTeamBoard && model.hasTeamPlan {
        TeamTaskBoardView()
      } else {
        VStack(spacing: 0) {
          MemoraSectionPicker(items: [false, true], selection: $showsCompleted) { completed in
            completed ? "完了" : "未完了"
          }
          .padding(.horizontal, MemoraSpacing.screen)
          .padding(.top, MemoraSpacing.sm)
          .padding(.bottom, MemoraSpacing.md)

          if isFiltered && !visibleTasks.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: MemoraSpacing.md) {
              Text(activeFilterText)
                .font(MemoraTypography.metadata)
                .foregroundStyle(MemoraPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              Button("解除") { todayOnly = false; waitingOnly = false }
                .font(MemoraTypography.secondary)
                .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
                .accessibilityLabel("絞り込みを解除")
            }
            .padding(.horizontal, MemoraSpacing.screen)
            .accessibilityIdentifier("tasks.activeFilters")
          }

          if model.isRecording {
            ActiveRecordingStrip()
              .padding(.horizontal, MemoraSpacing.lg)
              .padding(.bottom, MemoraSpacing.md)
          }

          if visibleTasks.isEmpty {
            ScrollView {
              MemoraEmptyState(icon: .checkmarkSquare,
                title: LocalizedStringKey(isFiltered ? "条件に合うタスクはありません" : (showsCompleted ? "完了したタスクはありません" : "タスクはありません")),
                message: LocalizedStringKey(isFiltered ? "条件を解除すると、ほかのタスクを確認できます。" : (showsCompleted ? "完了にした自分のタスクがここに残ります。" : "タスクを追加するか、記録から自分の担当を確認してください。")),
                actionTitle: isFiltered ? "絞り込みを解除" : (showsCompleted ? nil : "タスクを追加"),
                actionIcon: isFiltered ? .xmark : .plus) {
                if isFiltered {
                  todayOnly = false
                  waitingOnly = false
                } else {
                  model.isAddTaskPresented = true
                }
              }
              .padding(.top, MemoraSpacing.section)
              .padding(.bottom, model.bottomContentClearance)
            }
            .frame(maxHeight: .infinity)
          } else {
            MemoraList {
              if showsCompleted {
                ForEach(TaskHierarchy.ordered(completedFirst(visibleTasks))) { task in
                  taskRow(task, depth: taskDepths[task.id] ?? 0)
                }
              } else {
                ForEach(dueSections(of: visibleTasks)) { section in
                  Section(section.title) {
                    ForEach(section.tasks) { task in
                      taskRow(task, depth: taskDepths[task.id] ?? 0)
                    }
                  }
                }
              }
            }
            .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
            .refreshable { await model.refresh() }
          }
        }
      }
    }
      .background(MemoraPalette.background)
      .navigationTitle("タスク")
      .accessibilityAddTraits(.isHeader)
      .toolbar {
        if model.hasTeamPlan {
          ToolbarActionItem(usesSystemBackground: true) {
            Picker(selection: $showsTeamBoard) {
              Text("自分のタスク").tag(false)
              Text("チームボード").tag(true)
            } label: {
              ToolbarActionLabel("表示", icon: .person2)
            }
            .pickerStyle(.menu)
            .labelStyle(.iconOnly)
          }
          ToolbarActionGap()
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Toggle("今日取り組む", isOn: $todayOnly)
            Toggle("相手待ち", isOn: $waitingOnly)
          } label: {
            ToolbarActionLabel("タスクを絞り込み", icon: .line3HorizontalDecrease)
          }
          .accessibilityValue(isFiltered ? activeFilterText : "絞り込みなし")
          .disabled(showsTeamBoard)
        }

        // The create action is the rightmost item, matching the other tabs.
        ToolbarActionItem {
          ToolbarIconButton("タスクを追加", icon: .plus) {
            model.isAddTaskPresented = true
          }
          .labelStyle(.iconOnly)
          .disabled(showsTeamBoard)
        }
      }
      .sheet(isPresented: $model.isAddTaskPresented) {
        AddTaskView()
      }
      .sheet(item: $editingTask) { task in
        TaskEditView(task: task)
      }
      .onAppear { openPendingTaskIfNeeded() }
      .onChange(of: model.pendingTaskEditID) { _, _ in openPendingTaskIfNeeded() }
      .onChange(of: model.systemTaskFilterToday, initial: true) { _, request in
        guard let request else { return }
        todayOnly = request
        waitingOnly = false
        showsCompleted = false
        showsTeamBoard = false
        model.systemTaskFilterToday = nil
      }
  }

  private func taskRow(_ task: MemoraTask, depth: Int) -> some View {
    HStack(alignment: .top, spacing: 8) {
      TaskRow(task: task, showsSource: true) {
        editingTask = task
      }

      if let meetingID = task.meetingID, model.meetingTitles[meetingID] != nil {
        ToolbarIconButton("元の記録を開く", icon: .chevronRight) {
          model.homePath.append(.meeting(meetingID))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("「\(model.meetingTitles[meetingID] ?? "記録")」を開く")
      }
    }
    .padding(.leading, CGFloat(min(depth, 4)) * 12)
    .listRowBackground(Color.clear)
    .swipeActions(edge: .leading) {
      Button {
        model.toggleTask(task.id)
        let updated = model.tasks.first { $0.id == task.id }
        InteractionFeedback.shared.send(updated?.isCompleted == !task.isCompleted ? .selection : .error)
      } label: {
        Label(
          task.isCompleted ? "未完了に戻す" : "完了",
          icon: task.isCompleted ? .arrowUturnBackward : .checkmark
        )
      }
      .tint(.blue)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        InteractionFeedback.shared.send(.tap)
        model.deleteTask(task.id)
      } label: {
        Label("削除", icon: .trash)
      }
    }
    .contextMenu {
      Button("編集", icon: .pencil) { editingTask = task }
      Button("今日取り組む", icon: .sunMax) { model.setTaskWorkDate(task.id, to: .now) }
      if task.workDate != nil {
        Button("取り組む日を解除", icon: .xmark) { model.setTaskWorkDate(task.id, to: nil) }
      }
      Button("期限を今日に", icon: .sunMax) { model.setTaskDueDate(task.id, to: .now) }
      Button("期限を明日に", icon: .sunrise) {
        model.setTaskDueDate(task.id, to: Calendar.current.date(byAdding: .day, value: 1, to: .now))
      }
      Button("期限を来週に", icon: .calendar) {
        model.setTaskDueDate(task.id, to: Calendar.current.date(byAdding: .day, value: 7, to: .now))
      }
      if let meetingID = task.meetingID, model.meetingTitles[meetingID] != nil {
        Button("元の記録を開く", icon: .docText) { model.homePath.append(.meeting(meetingID)) }
      }
      Button("削除", icon: .trash, role: .destructive) { model.deleteTask(task.id) }
    }
  }

  private func openPendingTaskIfNeeded() {
    guard let id = model.pendingTaskEditID, let task = model.tasks.first(where: { $0.id == id }) else { return }
    model.pendingTaskEditID = nil
    showsCompleted = task.isCompleted
    showsTeamBoard = false
    editingTask = task
  }

  private var visibleTasks: [MemoraTask] {
    model.tasks.filter {
      model.isOwnTask($0) && $0.isCompleted == showsCompleted
        && (!todayOnly || $0.workDate.map { Calendar.current.isDateInToday($0) } == true)
        && (!waitingOnly || $0.progress == .waiting)
    }
  }

  private var activeFilterText: String {
    [todayOnly ? "今日取り組む" : nil, waitingOnly ? "相手待ち" : nil]
      .compactMap { $0 }.joined(separator: "・")
  }

  private func completedFirst(_ tasks: [MemoraTask]) -> [MemoraTask] {
    tasks.sorted { lhs, rhs in
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
  private func dueSections(of tasks: [MemoraTask]) -> [TaskDueSection] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today

    let ordered = tasks.sorted {
      ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
    }
    let grouped = Dictionary(grouping: ordered) { task in
      TaskDueBucket(task.dueDate, today: today, tomorrow: tomorrow, weekEnd: weekEnd, calendar: calendar)
    }
    // A fixed order, so 期限切れ stays on top even when sorting hid it.
    return TaskDueBucket.allCases.compactMap { bucket in
      grouped[bucket].map { TaskDueSection(bucket: bucket, tasks: TaskHierarchy.ordered($0)) }
    }
  }

}

/// A due-date heading and the tasks under it, for the tasks list.
private struct TaskDueSection: Identifiable {
  var bucket: TaskDueBucket
  var tasks: [MemoraTask]

  var id: TaskDueBucket { bucket }
  var title: String { bucket.title }
}

/// When a task is due, relative to today. Declared in the order the sections
/// read.
private enum TaskDueBucket: CaseIterable {
  case overdue, today, tomorrow, week, later, undated

  init(_ due: Date?, today: Date, tomorrow: Date, weekEnd: Date, calendar: Calendar) {
    guard let due else {
      self = .undated
      return
    }
    let day = calendar.startOfDay(for: due)
    if day < today {
      self = .overdue
    } else if day == today {
      self = .today
    } else if day == tomorrow {
      self = .tomorrow
    } else if day < weekEnd {
      self = .week
    } else {
      self = .later
    }
  }

  var title: String {
    switch self {
    case .overdue: "期限切れ"
    case .today: "今日"
    case .tomorrow: "明日"
    case .week: "7日以内"
    case .later: "それ以降"
    case .undated: "期限なし"
    }
  }
}
