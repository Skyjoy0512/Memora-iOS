import SwiftUI

struct MeetingTasksSection: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var editingTask: MemoraTask?
  @State private var isAddingTask = false

  var body: some View {
    let meetingTasks = model.tasks(forMeeting: meetingID)
    VStack(alignment: .leading, spacing: 12) {
      if meetingTasks.isEmpty {
        Text("この会議からタスクは見つかりませんでした")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(meetingTasks) { task in
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            TaskRow(task: task, showsMetadata: false) {
              editingTask = task
            }
            if task.ownerNeedsConfirmation == true {
              TaskOwnerConfirmation(task: task)
                .padding(.leading, MemoraSpacing.touchTarget + 12)
            }
          }
        }
      }

      Button("タスクを追加", icon: .textBadgePlus) {
        isAddingTask = true
      }
      .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
      .accessibilityIdentifier("meeting.tasks.add")
      .accessibilityHint("この会議に関連するタスクを作成します")
    }
    .sheet(item: $editingTask) { task in
      TaskEditView(task: task)
    }
    .sheet(isPresented: $isAddingTask) {
      AddTaskView(meetingID: meetingID)
    }
  }
}
