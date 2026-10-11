import SwiftUI

struct SummaryHistoryView: View {
  @Environment(MemoraModel.self) private var model
  @State private var restoreID: UUID?
  var meetingID: UUID

  var body: some View {
    let meeting = model.meeting(id: meetingID)
    let versions = meeting?.summaryVersions.reversed() ?? [].reversed()
    List {
      ForEach(Array(versions)) { version in
        NavigationLink {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              MarkdownDocumentView(markdown: version.markdown)
              Button("この要約を復元", icon: .arrowCounterclockwise) { restoreID = version.id }
                .buttonStyle(.bordered)
                .disabled(model.processing.isActive(meetingID))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
          }
          .navigationTitle("保存した要約")
          .navigationBarTitleDisplayMode(.inline)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(version.templateID.flatMap(model.summaryChoice)?.title ?? "旧形式・手動編集")
              .font(.headline)
            Text(version.generatedAt, format: .dateTime.year().month().day().hour().minute())
            Text("\(version.summaryLength.title) · \(version.modelInfo)")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("要約履歴")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("現在の要約も保存して復元します", isPresented: Binding {
      restoreID != nil
    } set: { if !$0 { restoreID = nil } }) {
      Button("復元") {
        if let restoreID { model.restoreSummary(restoreID, meetingID: meetingID) }
        restoreID = nil
      }
    } message: {
      Text("原音声・文字起こし・タスクは変更しません。")
    }
  }
}
