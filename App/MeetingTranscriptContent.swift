import SwiftUI

struct MeetingTranscriptContent: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text("文字起こし")
          .font(.title2.bold())
          .memoraTextReveal()

        if !meeting.transcript.isEmpty {
          Text(
            meeting.hasSpeakerSeparation
              ? "本文はタップすると修正できます。"
              : "この文字起こしは話者を分けていません。本文はタップすると修正できます。"
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      }

      if meeting.transcript.isEmpty {
        ContentUnavailableView {
          Label("文字起こし中", systemImage: "text.bubble")
        } description: {
          Text("完成した発言から、この画面に表示されます。")
        }
        .frame(maxWidth: .infinity)
      } else {
        LazyVStack(alignment: .leading, spacing: 22) {
          ForEach(meeting.transcript) { segment in
            TranscriptSegmentText(
              meetingID: meeting.id,
              segment: segment,
              showsSpeaker: meeting.hasSpeakerSeparation,
              timeWidth: 42
            )
          }
        }
      }
    }
    .memoraAppear()
  }
}

/// One transcript line whose body can be corrected in place. Used by both the
/// detail's transcript section and the full transcript screen.
struct TranscriptSegmentText: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  var segment: TranscriptSegment
  var showsSpeaker: Bool
  var timeWidth: CGFloat = 50
  var onEditSpeaker: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(MemoraFormat.duration(segment.timestamp))
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: timeWidth, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        if showsSpeaker {
          if let onEditSpeaker {
            Button(action: onEditSpeaker) {
              speakerLabel
            }
            .buttonStyle(.plain)
            .accessibilityHint("話者名を編集します")
          } else {
            speakerLabel
          }
        }

        InlineMarkdownEditor(
          text: segment.text,
          placeholder: "タップして入力",
          font: .body,
          minHeight: 60,
          onCommit: { model.updateTranscriptSegment(meetingID: meetingID, segmentID: segment.id, text: $0) }
        )
      }
    }
  }

  private var speakerLabel: some View {
    HStack(spacing: 4) {
      Text(segment.speaker)
        .font(.caption.weight(.semibold))
      if !segment.speakerIsCertain {
        Image(systemName: "questionmark")
          .font(.caption2.bold())
      }
    }
    .foregroundStyle(segment.speakerIsCertain ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
  }
}
