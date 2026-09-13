import SwiftUI

struct TaskRow: View {
  @Environment(MemoraModel.self) private var model
  var task: MemoraTask
  var showsSource = false

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

        HStack(spacing: 8) {
          if let assignee = task.assignee {
            Label(assignee, systemImage: "person")
          }
          if let dueDate = task.dueDate {
            Label(MemoraFormat.dueDate(dueDate), systemImage: "calendar")
              .foregroundStyle(dueDate < .now && !task.isCompleted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if showsSource, let meeting = model.meeting(id: task.meetingID) {
          Label(meeting.title, systemImage: "quote.bubble")
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      }
    }
    .contentShape(Rectangle())
  }
}
