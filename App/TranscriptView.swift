import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var editingSegment: TranscriptSegment?

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
              Text(meeting.title)
                .font(.title.bold())
              Text("話者名はタップして修正できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

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
                TranscriptSegmentRow(segment: segment) {
                  editingSegment = segment
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 18)
          .padding(.bottom, 20)
        }
        .navigationTitle("文字起こし")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSegment) { segment in
          SpeakerEditSheet(meetingID: meeting.id, segment: segment)
        }
      } else {
        ContentUnavailableView("文字起こしが見つかりません", systemImage: "doc.questionmark")
      }
    }
  }
}

private struct TranscriptSegmentRow: View {
  var segment: TranscriptSegment
  var editSpeaker: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(MemoraFormat.duration(segment.timestamp))
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())

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
          .foregroundStyle(segment.speakerIsCertain ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
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
