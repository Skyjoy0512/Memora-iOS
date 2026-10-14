import AppIntents

struct OpenMemoraMemoIntent: AppIntent {
  static var title: LocalizedStringResource = "Memoraでメモを書く"
  static var openAppWhenRun = true
  @Dependency private var model: MemoraModel

  @MainActor func perform() async throws -> some IntentResult {
    model.openSystemDestination(.newMemo)
    return .result()
  }
}
