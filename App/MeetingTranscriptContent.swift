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
