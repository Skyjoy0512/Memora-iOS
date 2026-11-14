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
  @State private var query = ""
  @AppStorage("memora.transcript.readable") private var usesReadableText = true

  var body: some View {
    // Each of these scans the transcript. Read once here rather than per line,
    // which made a long transcript quadratic on every playback tick.
    let showsSpeaker = !meeting.transcript.isEmpty
    let hasTimeline = self.hasTimeline
    let seekAction = hasTimeline ? self.seekAction : nil
    let segments = CollectionSearch.hasQuery(query) ? meeting.transcript.filter {
      CollectionSearch.matches(query, fields: [$0.text, $0.speaker])
    } : meeting.transcript

    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        if !meeting.transcript.isEmpty, meeting.audioURL != nil {
          Button("話者を端末内で解析", icon: .personWave2) {
            Task { await model.analyzeSpeakers(meeting.id) }
          }
          .disabled(model.speakerAnalysisIDs.contains(meeting.id) || model.processing.isActive(meeting.id))
          if let message = model.speakerAnalysisMessages[meeting.id] {
            Text(message).font(MemoraTypography.metadata).foregroundStyle(.secondary)
          }
        }
      }

      if meeting.transcript.isEmpty {
        switch meeting.status {
        case .waitingForTranscription:
          ManualAIProcessingCard(symbol: .textBubble, title: "文字起こし前", detail: "",
            actionTitle: "文字起こしする") { model.startTranscription(meeting.id) }
        case .importing, .transcribing:
          ProcessingOverview(meeting: meeting)
        case .failed(let message):
          FailureOverview(message: message) { model.retryProcessing(meeting.id) }
        default:
          Text("文字起こしはありません")
            .font(MemoraTypography.secondary)
            .foregroundStyle(MemoraPalette.textSecondary)
        }
      } else {
        TranscriptSearchControls(isReadable: $usesReadableText, query: $query)
        if CollectionSearch.hasQuery(query) {
          Text(segments.isEmpty ? "一致する発言はありません" : "\(segments.count)件の発言")
            .font(MemoraTypography.metadata).foregroundStyle(.secondary)
        }
        LazyVStack(alignment: .leading, spacing: 22) {
          ForEach(segments) { segment in
            TranscriptSegmentText(
              meetingID: meeting.id,
              segment: segment,
              showsSpeaker: showsSpeaker,
              usesReadableText: usesReadableText,
              showsTime: meeting.audioURL != nil || meeting.duration > 0,
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
    meeting.transcript.contains { $0.timestamp > 0 || ($0.endTime ?? 0) > $0.timestamp }
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
