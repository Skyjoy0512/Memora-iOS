import AppIntents

struct OpenAskAIIntent: AppIntent {
  static var title: LocalizedStringResource = "Ask AIを開く"
  static var openAppWhenRun = true
  @Dependency private var model: MemoraModel

  @MainActor func perform() async throws -> some IntentResult {
    model.openSystemDestination(.askAI)
    return .result()
  }
}
