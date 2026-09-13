import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var player = AudioPlaybackService()
  @State private var editingSegment: TranscriptSegment?

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
              transcriptHeader(meeting)

              if meeting.transcript.isEmpty {
                ContentUnavailableView {
                  Label("文字起こし中", systemImage: "text.bubble")
                } description: {
                  Text("完成した発言から、ここに表示されます。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
              } else {
                ForEach(meeting.transcript) { segment in
                  TranscriptSegmentRow(
                    segment: segment,
                    isActive: activeSegment(in: meeting)?.id == segment.id,
                    selectTimestamp: {
                      player.seek(to: segment.timestamp / max(player.duration, 1))
                    },
                    editSpeaker: {
                      editingSegment = segment
                    }
                  )
                  .id(segment.id)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
          }
          .onChange(of: activeSegment(in: meeting)?.id) { _, newValue in
            guard player.isPlaying, let newValue else { return }
            withAnimation(.smooth) {
              proxy.scrollTo(newValue, anchor: .center)
            }
          }
        }
        .safeAreaInset(edge: .bottom) {
          TranscriptPlayerBar(player: player, meeting: meeting)
        }
        .navigationTitle("文字起こし")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSegment) { segment in
          SpeakerEditSheet(meetingID: meeting.id, segment: segment)
        }
        .onAppear {
          player.configure(url: meeting.audioURL, fallbackDuration: meeting.duration)
        }
        .onDisappear {
          player.stop()
        }
      } else {
        ContentUnavailableView("文字起こしが見つかりません", systemImage: "doc.questionmark")
      }
    }
  }

  private func transcriptHeader(_ meeting: Meeting) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(meeting.title)
        .font(.title.bold())
      Text("再生位置に合わせて発言を追いかけます。話者名はタップして修正できます。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 8)
  }

  private func activeSegment(in meeting: Meeting) -> TranscriptSegment? {
    meeting.transcript.last { $0.timestamp <= player.currentTime }
  }
}

private struct TranscriptSegmentRow: View {
  var segment: TranscriptSegment
  var isActive: Bool
  var selectTimestamp: () -> Void
  var editSpeaker: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button(action: selectTimestamp) {
        Text(MemoraFormat.duration(segment.timestamp))
          .font(.caption.monospacedDigit().weight(.medium))
          .foregroundStyle(isActive ? .white : .indigo)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(isActive ? AnyShapeStyle(.indigo) : AnyShapeStyle(.indigo.opacity(0.08)), in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(MemoraFormat.duration(segment.timestamp))から再生")

      VStack(alignment: .leading, spacing: 7) {
        Button(action: editSpeaker) {
          HStack(spacing: 4) {
            Text(segment.speaker)
              .font(.caption.weight(.semibold))
            if !segment.speakerIsCertain {
              Image(systemName: "questionmark")
                .font(.caption2.bold())
            }
          }
          .foregroundStyle(segment.speakerIsCertain ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        }
        .buttonStyle(.plain)
        .accessibilityHint("話者名を編集します")

        Text(segment.text)
          .font(.body)
          .lineSpacing(4)
          .textSelection(.enabled)
      }
    }
    .padding(12)
    .background(isActive ? Color.indigo.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .animation(.smooth, value: isActive)
  }
}

private struct TranscriptPlayerBar: View {
  @Bindable var player: AudioPlaybackService
  var meeting: Meeting

  var body: some View {
    HStack(spacing: 12) {
      Button(player.isPlaying ? "一時停止" : "再生", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
        player.togglePlayback()
      }
      .labelStyle(.iconOnly)
      .font(.headline)
      .frame(width: 40, height: 40)
      .background(.indigo, in: Circle())
      .foregroundStyle(.white)

      VStack(spacing: 2) {
        Slider(
          value: Binding {
            player.currentTime / max(player.duration, 1)
          } set: { player.seek(to: $0) },
          in: 0...1
        ) {
          Text("音声の再生位置")
        }
        HStack {
          Text(MemoraFormat.duration(player.currentTime))
          Spacer()
          Text(MemoraFormat.duration(player.duration))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.regularMaterial)
  }
}

private struct SpeakerEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  var segment: TranscriptSegment
  @State private var name: String

  init(meetingID: UUID, segment: TranscriptSegment) {
    self.meetingID = meetingID
    self.segment = segment
    _name = State(initialValue: segment.speaker)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("話者") {
          TextField("名前", text: $name)
        }
        Section {
          Text("この発言の話者名だけを修正します。話者分離が曖昧な箇所は「？」で示します。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("話者を修正")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            model.renameSpeaker(meetingID: meetingID, segmentID: segment.id, name: name)
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
