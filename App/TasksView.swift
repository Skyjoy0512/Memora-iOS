import SwiftUI

struct TasksView: View {
  @Environment(MemoraModel.self) private var model
  @State private var showsCompleted = false
  @State private var path: [UUID] = []

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

                // A Button rather than a NavigationLink so List does not add a
                // second disclosure indicator next to this one.
                Button("元の会議を開く", systemImage: "chevron.right") {
                  path.append(task.meetingID)
                }
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 32, height: 44)
                .buttonStyle(.plain)
              }
              .padding(.vertical, 5)
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("タスク")
      .navigationDestination(for: UUID.self) { meetingID in
        MeetingDetailView(meetingID: meetingID)
      }
    }
  }

  private var visibleTasks: [MemoraTask] {
    model.tasks
      .filter { $0.isCompleted == showsCompleted }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }
}
