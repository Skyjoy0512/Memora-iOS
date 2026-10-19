import SwiftUI

/// "前回から": what earlier meetings of this series left open — unfinished
/// tasks, undecided points and what was decided — so the next one can start
/// where the last ended.
struct MeetingBriefSection: View {
  var brief: MeetingBrief
  var onOpenRecord: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("前回から", icon: .clockArrowCirclepath)
        .font(.headline)

      Button {
        onOpenRecord(brief.lastMeeting.id)
      } label: {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(brief.lastMeeting.displayTitle)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(2)
            Text(lastMeetingCaption)
              .font(.caption)
              .foregroundStyle(.secondary)
            if !brief.lastMeeting.summary.isEmpty {
              Text(brief.lastMeeting.shortSummaryPreview)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer(minLength: 8)
          Image(icon: .chevronRight)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(MemoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .memoraCard()
        .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityHint("前回の記録を開きます")

      if brief.isEmpty {
        Text("前回の記録に、残っているタスクや未決事項はありません。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if !brief.openTasks.isEmpty {
        group("未完了のタスク", count: brief.openTasks.count) {
          ForEach(brief.openTasks) { task in
            bullet(taskLine(task))
          }
        }
      }

      if !brief.openQuestions.isEmpty {
        group("まだ決まっていないこと", count: brief.openQuestions.count) {
          ForEach(brief.openQuestions.indices, id: \.self) { index in
            bullet(brief.openQuestions[index])
          }
        }
      }

      if !brief.decisions.isEmpty {
        group("前回決まったこと", count: brief.decisions.count) {
          ForEach(brief.decisions.indices, id: \.self) { index in
            bullet(brief.decisions[index])
          }
        }
      }
    }
  }

  private var lastMeetingCaption: String {
    let date = MemoraFormat.meetingDate(brief.lastMeeting.createdAt)
    return brief.recordCount > 1 ? "\(date) · これまで\(brief.recordCount)回" : date
  }

  private func taskLine(_ task: MemoraTask) -> String {
    var details: [String] = []
    if let assignee = task.assignee, !assignee.isEmpty { details.append(assignee) }
    if let due = task.dueDate { details.append(due.formatted(.dateTime.month().day())) }
    return details.isEmpty ? task.title : "\(task.title)（\(details.joined(separator: "・"))）"
  }

  private func group(_ title: String, count: Int, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(title) \(count)")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
    .accessibilityElement(children: .contain)
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("•")
        .foregroundStyle(.secondary)
      Text(InlineMarkdownEditor.attributed(text))
        .font(.subheadline)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
