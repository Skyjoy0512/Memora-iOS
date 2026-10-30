import SwiftUI
import WidgetKit

struct MemoraAskAIWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "app.bitrig.memora.ask-ai", provider: AskAIWidgetProvider()) { _ in
      AskAIWidgetContent().containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(MemoraAppLink.askAI.url)
    }
    .configurationDisplayName("Ask AI")
    .description("Memoraの会話を開き、すぐに質問します。")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

private struct AskAIWidgetContent: View {
  @Environment(\.widgetFamily) private var family
  var body: some View {
    if family == .accessoryCircular {
      Image(icon: .chatBubble, size: 22).accessibilityLabel("Ask AIを開く")
    } else if family == .accessoryInline {
      Label("Ask AI", icon: .chatBubble)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Image(icon: .chatBubble, size: 22).widgetAccentable()
        if family == .systemSmall || family == .systemMedium { Spacer(minLength: 0) }
        Text("Ask AI").font(.headline)
        if family != .accessoryRectangular { Text("Memoraに話しかける").font(.caption).foregroundStyle(.secondary) }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }
}

private struct AskAIWidgetEntry: TimelineEntry { var date: Date }
private struct AskAIWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> AskAIWidgetEntry { .init(date: .now) }
  func getSnapshot(in context: Context, completion: @escaping (AskAIWidgetEntry) -> Void) { completion(.init(date: .now)) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<AskAIWidgetEntry>) -> Void) {
    completion(Timeline(entries: [.init(date: .now)], policy: .never))
  }
}
