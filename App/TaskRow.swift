import SwiftUI

struct TaskRow: View {
  @Environment(MemoraModel.self) private var model
  var task: MemoraTask
  var showsSource = false
  /// Off where the row is read as part of a summary, so the assignee and due
  /// date do not add noise.
  var showsMetadata = true
  /// Called when the text is tapped, so the task can be edited.
  var onOpen: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button(task.isCompleted ? "未完了に戻す" : "完了にする", systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle") {
        withAnimation(.snappy) {
          model.toggleTask(task.id)
        }
      }
      .labelStyle(.iconOnly)
      .font(.title3)
      .foregroundStyle(task.isCompleted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

      VStack(alignment: .leading, spacing: 6) {
        Text(task.title)
          .font(.body)
          .strikethrough(task.isCompleted)
          .foregroundStyle(task.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .frame(maxWidth: .infinity, alignment: .leading)

        if showsMetadata {
          HStack(spacing: 8) {
            if let assignee = task.assignee {
              Text(assignee)
            }
            if let dueDate = task.dueDate {
              let isOverdue = dueDate < .now && !task.isCompleted
              if task.assignee != nil {
                Text("·")
              }
              if isOverdue {
                Text("期限切れ")
              }
              Text(MemoraFormat.dueDate(dueDate))
                .foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if showsSource, let meetingID = task.meetingID, let meeting = model.meeting(id: meetingID) {
          Text(meeting.title)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { onOpen?() }
    }
    .contentShape(Rectangle())
  }
}
