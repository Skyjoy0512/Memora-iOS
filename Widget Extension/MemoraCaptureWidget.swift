import SwiftUI
import WidgetKit

struct MemoraCaptureWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "app.bitrig.memora.capture", provider: MemoraTimelineProvider()) { entry in
      MemoraWidgetView(entry: entry)
        .containerBackground(for: .widget) {
          Color.black
        }
    }
    .configurationDisplayName("クイック記録")
    .description("Memoraを開いて、すぐに会話を記録します。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct MemoraWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: MemoraTimelineEntry

  var body: some View {
    Link(destination: URL(string: "memora://capture")!) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: "waveform")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)

        Spacer(minLength: 0)

        Text("会話を記録")
          .font(.headline)
          .foregroundStyle(.white)

        if family == .systemMedium {
          Text("録音から要点と次の行動まで、自動で整理")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(2)
        } else {
          Text("タップして開始")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.78))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}

private struct MemoraTimelineEntry: TimelineEntry {
  var date: Date
}

private struct MemoraTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> MemoraTimelineEntry {
    MemoraTimelineEntry(date: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (MemoraTimelineEntry) -> Void) {
    completion(MemoraTimelineEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MemoraTimelineEntry>) -> Void) {
    let entry = MemoraTimelineEntry(date: .now)
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60))))
  }
}
