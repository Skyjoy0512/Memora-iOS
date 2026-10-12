import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var detailTab: RootTab?
  @State private var editingSegment: TranscriptSegment?

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        // Scans the transcript, so it is read once rather than for every line.
        let showsSpeaker = meeting.hasSpeakerSeparation

        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title)
                  .font(.title.bold())
                if !meeting.transcript.isEmpty {
                  Text(
                    showsSpeaker
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
                  Label("文字起こし中", icon: .textBubble)
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
                    showsSpeaker: showsSpeaker,
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
        .background(MemoraPalette.background)
        .navigationTitle("文字起こし")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
          detailTab = model.selectedTab
          model.pushActiveDetail(meeting.id)
        }
        .onDisappear {
          model.popActiveDetail(meeting.id, tab: detailTab)
        }
        .sheet(item: $editingSegment) { segment in
          SpeakerEditSheet(meetingID: meeting.id, segment: segment)
        }
      } else {
        ContentUnavailableView("文字起こしが見つかりません", icon: .docQuestionmark)
      }
    }
  }
}


