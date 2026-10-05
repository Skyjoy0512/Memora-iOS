import SwiftUI

struct TaskRow: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var task: MemoraTask
  var showsSource = false
  /// Off where the row is read as part of a summary, so the assignee and due
  /// date do not add noise.
  var showsMetadata = true
  /// Called when the text is tapped, so the task can be edited.
  var onOpen: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy) {
          model.toggleTask(task.id)
        }
      } label: {
        Image(icon: task.isCompleted ? .checkmarkCircleFill : .circle)
          .symbolEffect(.bounce, options: .speed(1.6), value: reduceMotion ? false : task.isCompleted)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(task.isCompleted ? "未完了に戻す" : "完了にする")
      .sensoryFeedback(.selection, trigger: task.isCompleted)
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
          if !task.isCompleted, task.progress != .notStarted {
            Text(task.progress.label)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
          if !task.isCompleted, let workDate = task.workDate {
            Text(Calendar.current.isDateInToday(workDate) ? "今日取り組む" : "取り組む日: \(MemoraFormat.dueDate(workDate))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 8) {
            if let assignee = task.assignee {
              Text(assignee)
            }
            if let dueDate = task.dueDate {
              let overdue = isOverdue(dueDate)
              if task.assignee != nil {
                Text("·")
              }
              if overdue {
                Text("期限切れ")
              }
              Text(MemoraFormat.dueDate(dueDate))
                .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if showsSource, let title = sourceTitle {
          Text(title)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { onOpen?() }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(onOpen == nil ? Text("") : Text("タスクを編集します"))
      .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
    }
    .contentShape(Rectangle())
  }

  /// The source record's title, read from the model's title map so the row does
  /// not depend on the record itself.
  private var sourceTitle: String? {
    task.meetingID.flatMap { model.meetingTitles[$0] }
  }

  /// Overdue once the due day has passed. A task due today is not overdue
  /// just because the time stored with its date (often midnight) went by.
  private func isOverdue(_ dueDate: Date) -> Bool {
    !task.isCompleted && dueDate < Calendar.current.startOfDay(for: .now)
  }

  /// One sentence for VoiceOver, including the state the checkbox shows.
  private var accessibilityLabel: String {
    var parts = [task.title]
    if task.isCompleted {
      parts.append("完了")
    }
    if showsMetadata {
      if !task.isCompleted { parts.append(task.progress.label) }
      if let workDate = task.workDate { parts.append("取り組む日 \(MemoraFormat.dueDate(workDate))") }
      if let assignee = task.assignee {
        parts.append("担当 \(assignee)")
      }
      if let dueDate = task.dueDate {
        if isOverdue(dueDate) {
          parts.append("期限切れ")
        }
        parts.append(MemoraFormat.dueDate(dueDate))
      }
    }
    if showsSource, let title = sourceTitle {
      parts.append("元 \(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題の記録" : title)")
    }
    return parts.joined(separator: "、")
  }
}
