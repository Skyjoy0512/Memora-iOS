import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var editingSegment: TranscriptSegment?

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title)
                  .font(.title.bold())
                if !meeting.transcript.isEmpty {
                  Text(
                    meeting.hasSpeakerSeparation
                      ? "話者名と本文はタップして修正できます。"
                      : "この文字起こしは話者を分けていません。本文はタップすると修正できます。"
                  )
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                }
              }
              .padding(.top, 8)
              .padding(.bottom, 12)

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
                  TranscriptSegmentText(
                    meetingID: meeting.id,
                    segment: segment,
                    showsSpeaker: meeting.hasSpeakerSeparation,
                    timeWidth: 62,
                    onEditSpeaker: { editingSegment = segment }
                  )
                  .padding(.vertical, 2)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
          }
          .scrollFocusedEditorAboveKeyboard(in: proxy)
        }
        .navigationTitle("文字起こし")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
          model.activeDetailMeetingID = meeting.id
        }
        .onDisappear {
          if model.activeDetailMeetingID == meeting.id {
            model.activeDetailMeetingID = nil
          }
        }
        .sheet(item: $editingSegment) { segment in
          SpeakerEditSheet(meetingID: meeting.id, segment: segment)
        }
      } else {
        ContentUnavailableView("文字起こしが見つかりません", systemImage: "doc.questionmark")
      }
    }
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
