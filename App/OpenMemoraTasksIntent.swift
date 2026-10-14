import AppIntents

struct OpenMemoraTasksIntent: AppIntent {
  static var title: LocalizedStringResource = "Memoraの今日のタスクを開く"
  static var openAppWhenRun = true
  @Dependency private var model: MemoraModel

  @MainActor func perform() async throws -> some IntentResult {
    model.openSystemDestination(.todayTasks)
    return .result()
  }
}
