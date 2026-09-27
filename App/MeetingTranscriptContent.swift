import SwiftUI

struct MeetingTranscriptContent: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting
  /// The recording's playback, when there is one to follow.
  var player: AudioPlayerService?
  /// A line to highlight even when nothing is playing, e.g. an AI source time.
  var focusedSegmentID: UUID?
  @State private var editingSpeakerSegment: TranscriptSegment?

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
          Label("文字起こし中", icon: .textBubble)
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
              timeWidth: 42,
              isActive: segment.id == activeSegmentID || segment.id == focusedSegmentID,
              onSeek: seekAction,
              onEditSpeaker: meeting.hasSpeakerSeparation
                ? { editingSpeakerSegment = segment }
                : nil
            )
            .id(segment.id)
          }
        }
      }
    }
    .memoraAppear()
    .sheet(item: $editingSpeakerSegment) { segment in
      SpeakerEditSheet(meetingID: meeting.id, segment: segment)
    }
  }

  /// The line being played, so it can be highlighted.
  private var activeSegmentID: UUID? {
    guard hasTimeline, let player else { return nil }
    return meeting.transcript.last { $0.timestamp <= player.currentTime }?.id
  }

  /// Seeking is only offered when the transcript actually carries times.
  private var seekAction: ((TimeInterval) -> Void)? {
    guard hasTimeline, let player else { return nil }
    return { time in
      player.seek(to: time)
      player.play()
    }
  }

  private var hasTimeline: Bool {
    meeting.transcript.contains { $0.timestamp > 0 }
  }
}

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
