import SwiftUI

struct SummaryHistoryView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID

  var body: some View {
    let meeting = model.meeting(id: meetingID)
    let versions = meeting?.summaryVersions.reversed() ?? [].reversed()
    MemoraForm {
      ForEach(Array(versions)) { version in
        NavigationLink {
          SummaryHistoryDetailView(meetingID: meetingID, version: version)
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
  }
}
