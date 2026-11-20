import SwiftUI

struct SummaryHistoryDetailView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  var version: TemplateSummary
  @State private var confirmsRestoration = false
  @State private var restorationFailed = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        MarkdownDocumentView(markdown: version.markdown)
        Button("この要約を復元", icon: .arrowCounterclockwise) { confirmsRestoration = true }
          .buttonStyle(.bordered)
          .disabled(model.processing.isActive(meetingID))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MemoraSpacing.xl)
    }
    .navigationTitle("保存した要約")
    .navigationBarTitleDisplayMode(.inline)
    // Presentation belongs to the visible destination, not the hidden list.
    .confirmationDialog("現在の要約も保存して復元します", isPresented: $confirmsRestoration) {
      Button("復元") { restorationFailed = !model.restoreSummary(version.id, meetingID: meetingID) }
    } message: {
      Text("原音声・文字起こし・タスクは変更しません。")
    }
    .alert("要約を復元できませんでした", isPresented: $restorationFailed) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text("現在の要約を保持しています。記録の状態や保存先を確認して、もう一度お試しください。")
    }
  }
}
