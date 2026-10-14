import AppIntents

/// Configuration is resolved in both host and extension processes. Keeping the
/// same public identity in their shared sources avoids a file-private type ID.
struct MemoraProjectWidgetConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "プロジェクトを選択"
  @Parameter(title: "プロジェクト") var project: WidgetProjectEntity?

  init() {}
  init(project: WidgetProjectEntity?) { self.project = project }
}
