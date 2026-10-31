import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var detailTab: RootTab?
  @State private var editingSegment: TranscriptSegment?
  @AppStorage("memora.transcript.readable") private var usesReadableText = true

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        // Scans the transcript, so it is read once rather than for every line.
        let showsSpeaker = meeting.hasSpeakerSeparation

        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              VStack(alignment: .leading, spacing: 8) {
                Text(meeting.displayTitle)
                  .font(MemoraTypography.screenTitle)
              }
              .padding(.top, MemoraSpacing.sm)
              .padding(.bottom, MemoraSpacing.md)

              if meeting.transcript.isEmpty {
                ContentUnavailableView {
                  Label("文字起こし中", icon: .textBubble)
                } description: {
                  Text("完成した発言から、ここに表示されます。")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MemoraSpacing.group)
              } else {
                TranscriptReadingOptions(isReadable: $usesReadableText)
                ForEach(meeting.transcript) { segment in
                  TranscriptSegmentText(
                    meetingID: meeting.id,
                    segment: segment,
                    showsSpeaker: showsSpeaker,
                    usesReadableText: usesReadableText,
                    showsTime: meeting.audioURL != nil || meeting.duration > 0,
                    timeWidth: 62,
                    onEditSpeaker: { editingSegment = segment }
                  )
                  .padding(.vertical, MemoraSpacing.xxs)
                }
              }
            }
            .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
            .padding(.horizontal, MemoraSpacing.screen)
            .padding(.bottom, MemoraSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .center)
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
