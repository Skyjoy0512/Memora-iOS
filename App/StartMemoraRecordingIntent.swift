import AppIntents

struct StartMemoraRecordingIntent: AppIntent {
  static var title: LocalizedStringResource = "Memoraで録音を開始"
  static var openAppWhenRun = true
  @Dependency private var model: MemoraModel

  @MainActor func perform() async throws -> some IntentResult {
    guard !AppLockService.isEnabled, !model.isRestoring, !model.isStoreProtected else { throw MemoraIntentFailure.openAppToRecord }
    await model.startCapture(spaceID: model.visibleProjectID)
    guard model.isRecording, !model.isRecordingPaused else { throw MemoraIntentFailure.recordingNotStarted }
    return .result()
  }
}
