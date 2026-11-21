#if DEBUG
import SwiftUI

/// Explicit fixtures exercise the actual summary editor and SQLite save path.
struct DesignSystemReviewView: View {
  @Environment(MemoraModel.self) private var model
  @State private var result = "未検証"
  @State private var isSelectingFiles = false
  @State private var selectedFiles: Set<UUID> = []

  var body: some View {
    MemoraList {
      Section("予定の表示例・保存しません") {
        UpcomingEventCard(meeting: DesignReviewFixture.upcomingMeeting)
          .accessibilityIdentifier("design.review.upcoming")
      }
      Section("ファイル選択の表示例・保存しません") {
        Button(isSelectingFiles ? "選択を終了" : "複数選択") { isSelectingFiles.toggle() }
        ForEach(DesignReviewFixture.selectionRecords) { meeting in
          Button {
            if isSelectingFiles, !selectedFiles.insert(meeting.id).inserted {
              selectedFiles.remove(meeting.id)
            }
          } label: {
            LibraryRecordRow(meeting: meeting, showsPreview: true, reservesSelectionSpace: true,
              isSelecting: isSelectingFiles,
              isSelected: selectedFiles.contains(meeting.id))
          }
          .buttonStyle(.plain)
        }
      }
      Section {
        Text("表示確認専用の架空の記録を作ります。AI・外部API・録音は使いません。検証後はこの画面から削除できます。")
          .font(MemoraTypography.metadata)
        Button("検証用の要約を作成") { result = DesignReviewFixture.prepare(in: model) ? "検証用の要約を保存しました" : "保存できませんでした" }
        if model.meeting(id: DesignReviewFixture.recordID) != nil {
          NavigationLink("検証用の要約を開く") {
            MeetingDetailView(meetingID: DesignReviewFixture.recordID, showsLocalPlaybackBar: true)
          }
        }
        Button("SQLiteの保存を確認") { result = DesignReviewFixture.verify(in: model) }
        Text(result).accessibilityIdentifier("design.review.result")
        Button("検証データを片付ける", role: .destructive) {
          result = DesignReviewFixture.cleanup(in: model) ? "検証データを削除しました" : "削除できませんでした"
        }
      }
      Section("長文の表示（架空）") {
        NavigationLink("長文Markdownを読む") {
          ScrollView {
            AIResponseText(text: DesignReviewFixture.markdown)
              .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
              .padding(MemoraSpacing.screen)
              .frame(maxWidth: .infinity)
          }
          .background(MemoraPalette.background)
          .navigationTitle("長文Markdown").navigationBarTitleDisplayMode(.inline)
        }
      }
    }
    .navigationTitle("デザインと保存の検証").navigationBarTitleDisplayMode(.inline)
  }
}
#endif
