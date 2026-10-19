import SwiftUI

/// A teammate's shared record, read-only. It is drawn like a record of one's
/// own, but says whose it is and that it cannot be edited here.
struct SharedRecordView: View {
  @Environment(MemoraModel.self) private var model
  var recordID: String

  var body: some View {
    if let record = model.cloudSharing.sharedRecord(id: recordID) {
      let meeting = record.meeting

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header(record)

          CollapsibleInsightSection(.summary, showsDivider: false) {
            if meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text("要約はありません")
                .foregroundStyle(.secondary)
            } else if MarkdownBlockParser.hasBlockStructure(meeting.summary) {
              MarkdownDocumentView(markdown: meeting.summary, isLazy: true)
                .textSelection(.enabled)
            } else {
              Text(InlineMarkdownEditor.attributed(meeting.summary))
                .lineSpacing(6)
                .textSelection(.enabled)
            }
          }

          CollapsibleInsightSection(.decisions) {
            bullets(meeting.decisions, empty: "明確な決定はありません")
          }

          CollapsibleInsightSection(.tasks) {
            if record.tasks.isEmpty {
              Text("タスクはありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(record.tasks) { task in
                  taskRow(task)
                }
              }
            }
          }

          CollapsibleInsightSection(.openQuestions) {
            bullets(meeting.openQuestions, empty: "未決事項はありません")
          }

          CollapsibleInsightSection(.keyPoints) {
            bullets(meeting.keyPoints, empty: "ポイントはありません")
          }

          if !meeting.transcript.isEmpty {
            transcript(meeting)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.lg)
        .padding(.bottom, MemoraSpacing.section)
      }
      .navigationTitle(meeting.displayTitle)
      .navigationBarTitleDisplayMode(.inline)
    } else {
      ContentUnavailableView(
        "共有が見つかりません",
        icon: .person3,
        description: Text("共有が停止されたか、まだ読み込まれていません。")
      )
    }
  }

  private func header(_ record: SharedRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      SharedOwnerBadge(ownerName: record.ownerName)

      Text(record.meeting.displayTitle)
        .font(.largeTitle.bold())
        .tracking(-0.6)

      HStack(spacing: 8) {
        Text(MemoraFormat.meetingDate(record.meeting.createdAt))
        Text("·")
        Text(MemoraFormat.duration(record.meeting.duration))
        if let project = record.projectName {
          Text("·")
          Label(project, icon: .folder)
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)

      Label("\(record.ownerName)さんの記録です。閲覧のみで、編集はできません。", icon: .lock)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(.top, MemoraSpacing.sm)
  }

  @ViewBuilder
  private func bullets(_ items: [String], empty: String) -> some View {
    if items.isEmpty {
      Text(empty)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(items.indices, id: \.self) { index in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
              .fill(Color.primary)
              .frame(width: 5, height: 5)
            Text(InlineMarkdownEditor.attributed(items[index]))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .textSelection(.enabled)
    }
  }

  private func taskRow(_ task: MemoraTask) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(icon: task.isCompleted ? .checkmarkCircleFill : .circle)
        .foregroundStyle(task.isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .strikethrough(task.isCompleted)
        if let assignee = task.assignee, !assignee.isEmpty {
          Text(assignee)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(task.isCompleted ? "完了" : "未完了")
  }

  private func transcript(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
        .padding(.bottom, MemoraSpacing.sm)
      Label("文字起こし", icon: .textBubble)
        .font(.title3.bold())

      LazyVStack(alignment: .leading, spacing: 16) {
        ForEach(meeting.transcript) { segment in
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text(MemoraFormat.duration(segment.timestamp))
                .monospacedDigit()
              if meeting.hasSpeakerSeparation {
                Text(segment.speaker)
                  .fontWeight(.semibold)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(segment.text)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .textSelection(.enabled)
    }
  }
}
