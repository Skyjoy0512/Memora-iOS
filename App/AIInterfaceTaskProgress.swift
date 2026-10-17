import SwiftUI

/// The counts come from authorized current tasks, never a generated value.
///
/// The headline number and the bar are derived from the tasks the model passed;
/// completion is shown per task only when the list has more than one entry, so
/// a single task stays a one-line statement. The headline-number treatment
/// follows OpenUI's `MetricIndicator` (MIT, 8d9c4c3b) as an independent Swift
/// implementation.
struct AIInterfaceTaskProgress: View {
  var tasks: [MemoraTask]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let summary = AIInterfaceTaskProgressSummary(tasks: tasks)
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(summary.accessibilityValue).font(.subheadline)
        Spacer(minLength: 0)
        if summary.isComplete {
          Label("完了", icon: .checkmarkCircleFill).font(.caption).foregroundStyle(MemoraPalette.textSecondary)
        } else if summary.remaining > 0 {
          Text("残り\(summary.remaining)件").font(.caption).foregroundStyle(MemoraPalette.textSecondary)
        }
      }
      ProgressView(value: summary.fraction)
        .tint(MemoraPalette.textPrimary)
        .animation(reduceMotion ? nil : .smooth, value: summary.completed)
        .accessibilityLabel("タスクの完了状況")
        .accessibilityValue(summary.accessibilityValue)
      if tasks.count >= 2 {
        DisclosureGroup("内訳") {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(tasks) { task in
              Label {
                Text(task.title).font(.subheadline)
              } icon: {
                Image(icon: task.isCompleted ? .checkmarkCircleFill : .circle)
              }
              .accessibilityLabel("\(task.title)。\(task.isCompleted ? "完了" : "未完了")")
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 4)
        }
        .font(.subheadline)
        .tint(.primary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
