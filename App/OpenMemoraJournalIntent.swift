import AppIntents

struct OpenMemoraJournalIntent: AppIntent {
  static var title: LocalizedStringResource = "Memoraのジャーナルを開く"
  static var openAppWhenRun = true
  @Dependency private var model: MemoraModel

  @MainActor func perform() async throws -> some IntentResult {
    model.openSystemDestination(.journal)
    return .result()
  }
}
