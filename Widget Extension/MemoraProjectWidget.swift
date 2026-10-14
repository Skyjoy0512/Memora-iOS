import AppIntents
import SwiftUI
import WidgetKit

struct MemoraProjectWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "app.bitrig.memora.project", intent: MemoraProjectWidgetConfiguration.self, provider: ProjectWidgetProvider()) { entry in
      VStack(alignment: .leading, spacing: 8) {
        if let project = entry.project {
          Text(project.name).font(.headline).lineLimit(2).privacySensitive()
          Text("未完了タスク \(project.openTaskCount)件").font(.subheadline).privacySensitive()
          if let date = project.lastRecordAt { Text("最近の記録 \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary).privacySensitive() }
        } else {
          Label("プロジェクト", icon: .folder).font(.headline)
          Text(MemoraWidgetSnapshotStore.fileURL == nil ? "情報共有は未設定" : "ウィジェットを編集してプロジェクトを選択")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .containerBackground(for: .widget) { Color(.systemBackground) }
      .widgetURL(entry.project.map { MemoraAppLink.project($0.id).url } ?? MemoraAppLink.projects.url)
    }
    .configurationDisplayName("プロジェクト")
    .description("共有を許可したプロジェクトのタスクと最近の記録を確認します。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct ProjectWidgetEntry: TimelineEntry { var date: Date; var project: MemoraWidgetSnapshot.Project? }
private struct ProjectWidgetProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> ProjectWidgetEntry { .init(date: .now) }
  func snapshot(for configuration: MemoraProjectWidgetConfiguration, in context: Context) async -> ProjectWidgetEntry {
    .init(date: .now, project: MemoraWidgetSnapshotStore.read()?.projects.first { $0.id == configuration.project?.id })
  }
  func timeline(for configuration: MemoraProjectWidgetConfiguration, in context: Context) async -> Timeline<ProjectWidgetEntry> {
    Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .after(.now.addingTimeInterval(15 * 60)))
  }
}
