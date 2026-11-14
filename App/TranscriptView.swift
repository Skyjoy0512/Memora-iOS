import SwiftUI

struct TranscriptView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var detailTab: RootTab?

  var body: some View {
    Group {
      if let meeting = model.meeting(id: meetingID) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              VStack(alignment: .leading, spacing: 8) {
                Text(meeting.displayTitle)
                  .font(MemoraTypography.screenTitle)
              }
              .padding(.top, MemoraSpacing.sm)
              .padding(.bottom, MemoraSpacing.md)

              MeetingTranscriptContent(meeting: meeting, player: nil, focusedSegmentID: nil)
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
        .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      } else {
        ContentUnavailableView("文字起こしが見つかりません", icon: .docQuestionmark)
      }
    }
  }
}
