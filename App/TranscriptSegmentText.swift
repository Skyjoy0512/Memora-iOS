import SwiftUI

/// One transcript line whose body can be corrected in place. Used by both the
/// detail's transcript section and the full transcript screen.
struct TranscriptSegmentText: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var meetingID: UUID
  var segment: TranscriptSegment
  var showsSpeaker: Bool
  var timeWidth: CGFloat = 50
  /// Highlighted while the recording is playing this line.
  var isActive = false
  /// Set when the line's time can be played from.
  var onSeek: ((TimeInterval) -> Void)?
  var onEditSpeaker: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      timeLabel

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
          onCommit: { text in
            model.updateTranscriptSegment(meetingID: meetingID, segmentID: segment.id, text: text)
            return true
          }
        )
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(0.06))
      }
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
  }

  /// The time is tappable only when the recording can actually play from it.
  @ViewBuilder
  private var timeLabel: some View {
    if let onSeek {
      Button {
        onSeek(segment.timestamp)
      } label: {
        timeText
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(MemoraFormat.duration(segment.timestamp)) から再生")
    } else {
      timeText
    }
  }

  private var timeText: some View {
    Text(MemoraFormat.duration(segment.timestamp))
      .font(.caption.monospacedDigit().weight(isActive ? .bold : .medium))
      .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(width: timeWidth, alignment: .leading)
  }

  private var speakerLabel: some View {
    HStack(spacing: 4) {
      Text(segment.speaker)
        .font(.caption.weight(.semibold))
      if !segment.speakerIsCertain {
        Image(icon: .questionmark)
          .font(.caption2.bold())
      }
    }
    .foregroundStyle(.primary)
  }
}
