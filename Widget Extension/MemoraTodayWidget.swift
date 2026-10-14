import SwiftUI
import WidgetKit

struct MemoraTodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "app.bitrig.memora.today", provider: TodayWidgetProvider()) { entry in
      TodayWidgetContent(entry: entry).containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(MemoraAppLink.journal.url)
    }
    .configurationDisplayName("今日のMemora")
    .description("共有を許可した件数と次の予定の時刻を確認します。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct TodayWidgetContent: View {
  @Environment(\.widgetFamily) private var family
  var entry: TodayWidgetEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(entry.date, format: .dateTime.month().day().weekday()).font(.caption).foregroundStyle(.secondary)
      if let snapshot = entry.snapshot {
        Text("未完了タスク").font(.subheadline)
        Text(snapshot.openTaskCount, format: .number).font(.largeTitle.weight(.semibold)).privacySensitive()
        if family == .systemMedium {
          HStack {
            Text("今日の記録 \(snapshot.recordCount)件")
            Spacer()
            if let next = snapshot.nextEventAt, next > entry.date { Text(next, format: .dateTime.hour().minute()) }
          }.font(.caption).privacySensitive()
        }
      } else {
        Text("今日のMemora").font(.headline)
        Text(MemoraWidgetSnapshotStore.fileURL == nil ? "情報共有は未設定" : "アプリで最新の状態を確認")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

private struct TodayWidgetEntry: TimelineEntry { var date: Date; var snapshot: MemoraWidgetSnapshot? }
private struct TodayWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayWidgetEntry { .init(date: .now) }
  func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) { completion(.init(date: .now, snapshot: MemoraWidgetSnapshotStore.read())) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
    completion(Timeline(entries: [.init(date: .now, snapshot: MemoraWidgetSnapshotStore.read())], policy: .after(.now.addingTimeInterval(15 * 60))))
  }
}
