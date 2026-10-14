import AppIntents

struct OpenMemoraProjectIntent: OpenIntent {
  static var title: LocalizedStringResource = "Memoraのプロジェクトを開く"
  @Parameter(title: "プロジェクト") var target: MemoraProjectEntity
  @Dependency private var model: MemoraModel
  static var parameterSummary: some ParameterSummary { Summary("\(\.$target)を開く") }

  @MainActor func perform() async throws -> some IntentResult {
    guard !AppLockService.isEnabled, !model.isRestoring, !model.isStoreProtected,
          model.currentTeamID == nil, model.space(id: target.id) != nil else { throw MemoraIntentFailure.projectUnavailable }
    model.openProject(target.id)
    return .result()
  }
}
