import SwiftUI

struct JournalDailyRecapCard: View {
  @Environment(MemoraModel.self) private var model
  var date: Date
  var onOpenDetails: () -> Void

  var body: some View {
    let recap = JournalDailyRecap.build(date: date, meetings: model.meetings,
      tasks: model.tasks, entries: model.lifeLogEntries)
    VStack(alignment: .leading, spacing: 14) {
      Text(recap.heading)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(recap.narrative)
        .font(.subheadline)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
      if !recap.highlights.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(recap.highlights.enumerated()), id: \.offset) { _, text in
            Text(text).font(.subheadline).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      if !recap.isFuture {
        Text("保存された記録から作成。イベントの実施や気分は推測しません。")
          .font(.caption).foregroundStyle(.secondary)
        Button("詳しい振り返り・健康データ", action: onOpenDetails)
          .font(.subheadline)
          .frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .memoraCard(radius: 20)
  }
}
