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
    let context = showsMetadata ? TaskContextLine.text(progress: task.progress,
      workDate: task.workDate, isCompleted: task.isCompleted) : nil
    HStack(alignment: .top, spacing: 12) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy) {
          model.toggleTask(task.id)
        }
        let updated = model.tasks.first { $0.id == task.id }
        InteractionFeedback.shared.send(updated?.isCompleted == !task.isCompleted ? .selection : .error)
      } label: {
        Image(icon: task.isCompleted ? .checkmarkCircleFill : .circle, size: MemoraIconMetrics.glyph)
          .contentTransition(.opacity)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("\(task.title)を\(task.isCompleted ? "未完了に戻す" : "完了にする")")
      .accessibilityValue(task.isCompleted ? "完了" : "未完了")
      .buttonStyle(.plain)
      .labelStyle(.iconOnly)
      .font(.title3)
      .foregroundStyle(task.isCompleted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

      VStack(alignment: .leading, spacing: 6) {
        Text(task.title)
          .font(.body)
          .strikethrough(task.isCompleted)
          .foregroundStyle(task.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .frame(maxWidth: .infinity, alignment: .leading)

        if let context {
          Text(context)
            .font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("task.context.\(task.id)")
        }

        if showsMetadata, !task.isCompleted, let dueDate = task.dueDate {
          let overdue = isOverdue(dueDate)
          HStack(spacing: 8) {
            if overdue {
              Text("期限切れ")
            }
            Text(MemoraFormat.dueDate(dueDate))
          }
          .font(MemoraTypography.metadata)
          .foregroundStyle(overdue ? MemoraPalette.danger : MemoraPalette.textSecondary)
        }
        if showsSource, let sourceTitle {
          Text(sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題の記録" : sourceTitle)
            .font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(2)
        }
      }
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture {
        guard let onOpen else { return }
        InteractionFeedback.shared.send(.tap)
        onOpen()
      }
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
