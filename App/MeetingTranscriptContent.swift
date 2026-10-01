import SwiftUI

struct MeetingTranscriptContent: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting
  /// The recording's playback, when there is one to follow.
  var player: AudioPlayerService?
  /// A line to highlight even when nothing is playing, e.g. an AI source time.
  var focusedSegmentID: UUID?
  @State private var editingSpeakerSegment: TranscriptSegment?
  /// The line being played. Kept here and set by `ActiveSegmentTracker`, so
  /// the list redraws when playback moves to another line, not on every tick.
  @State private var activeSegmentID: UUID?

  var body: some View {
    // Each of these scans the transcript. Read once here rather than per line,
    // which made a long transcript quadratic on every playback tick.
    let showsSpeaker = meeting.hasSpeakerSeparation
    let hasTimeline = self.hasTimeline
    let seekAction = hasTimeline ? self.seekAction : nil

    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text("文字起こし")
          .font(.title2.bold())
          .memoraTextReveal()

        if !meeting.transcript.isEmpty {
          Text(
            showsSpeaker
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
              showsSpeaker: showsSpeaker,
              timeWidth: 42,
              isActive: segment.id == activeSegmentID || segment.id == focusedSegmentID,
              onSeek: seekAction,
              onEditSpeaker: showsSpeaker
                ? { editingSpeakerSegment = segment }
                : nil
            )
            .id(segment.id)
          }
        }
      }
    }
    .memoraAppear()
    .background {
      if hasTimeline, let player {
        ActiveSegmentTracker(
          player: player,
          transcript: meeting.transcript,
          activeSegmentID: $activeSegmentID
        )
      }
    }
    .sheet(item: $editingSpeakerSegment) { segment in
      SpeakerEditSheet(meetingID: meeting.id, segment: segment)
    }
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

/// Reads the fast-ticking playback position in a view of its own, and passes
/// on only the line it falls in.
private struct ActiveSegmentTracker: View {
  var player: AudioPlayerService
  var transcript: [TranscriptSegment]
  @Binding var activeSegmentID: UUID?

  var body: some View {
    let current = transcript.last { $0.timestamp <= player.currentTime }?.id
    Color.clear
      .onChange(of: current, initial: true) { _, newValue in
        activeSegmentID = newValue
      }
  }
}
