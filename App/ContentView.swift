import SwiftUI

struct ContentView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var appLock = AppLockService()
  @AppStorage("memora.prefersDarkAppearance") private var prefersDarkAppearance = false

  var body: some View {
    @Bindable var model = model

    Group {
      if model.hasCompletedOnboarding {
        RootTabView()
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      } else {
        OnboardingView {
          model.completeOnboarding()
          Task {
            await model.startCapture()
          }
        } showSample: {
          model.completeOnboarding()
          model.loadSampleContent()
        } skip: {
          model.completeOnboarding()
        }
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.hasCompletedOnboarding)
    .background { GestureHapticsInstaller() }
    .sheet(isPresented: $model.isCapturePresented, onDismiss: {
      model.completeCaptureDismissal()
    }) {
      CaptureSessionView()
    }
    .sheet(isPresented: $model.isSettingsPresented) {
      SettingsView()
    }
    .sheet(isPresented: $model.isToolsPresented) {
      NavigationStack { ToolsView() }
    }
    .sheet(isPresented: $model.isAuthPresented) {
      AuthView()
    }
    .sheet(isPresented: $model.isPaywallPresented) {
      PaywallView()
    }
    .overlay {
      if model.isImporting {
        ImportProgressOverlay(progress: model.importProgress)
          .transition(.opacity)
      }
    }
    .overlay { lockOverlay }
    .onAppear { appLock.lockIfEnabled() }
    .modifier(WidgetSnapshotUpdates())
    .task { await model.refreshWidgetSnapshot() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.scheduleWidgetSnapshot()
        model.resumePendingSummariesIfNeeded()
      }
      if phase == .background { model.scheduleBackgroundSummary() }
      appLock.handleScenePhase(phase, isRecording: model.isRecording)
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isImporting)
    .preferredColorScheme(prefersDarkAppearance ? .dark : nil)
    .alert("マイクへのアクセスが必要です", isPresented: $model.microphonePermissionDenied) {
      Button("設定を開く") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          openURL(url)
        }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("録音は許可した時だけ始まります。設定でマイクを許可すると、会話をこのiPhoneに保存できます。")
    }
    .alert("録音を開始できませんでした", isPresented: recordingErrorBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.recordingErrorMessage ?? "もう一度お試しください。")
    }
    .alert("録音を保存できませんでした", isPresented: $model.isUnsavedRecordingAlertPresented) {
      Button("再試行") {
        Task { await model.retrySavingRecording() }
      }
      Button("あとで", role: .cancel) {}
    } message: {
      Text("録音と下書きは端末に残っています。保存できるまで、新しい録音は始められません。「再試行」で保存してください。")
    }
    .alert("インポートできませんでした", isPresented: importErrorBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.importErrorMessage ?? "別の音声ファイルをお試しください。")
    }
    .alert("保存先が変更されました", isPresented: Binding(
      get: { model.projectFilingNotice != nil },
      set: { if !$0 { model.projectFilingNotice = nil } }
    )) {
      Button("OK", role: .cancel) { model.projectFilingNotice = nil }
    } message: {
      Text(model.projectFilingNotice ?? "")
    }
    .alert("音声を取り込みます", isPresented: pendingImportNoticeBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.pendingImportNotice ?? "")
    }
    .alert("取り込まれていない音声があります", isPresented: pendingInboxBinding) {
      Button("取り込む") { Task { await model.importInboxAudio() } }
      Button("削除", role: .destructive) { model.discardInboxAudio() }
      Button("あとで", role: .cancel) { model.pendingInboxCount = nil }
    } message: {
      Text("\(model.pendingInboxCount ?? 0)件の音声が、前回の取り込みの途中で残っています。")
    }
    .alert("保存データを読み込めませんでした", isPresented: loadFailureBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.loadFailureMessage ?? "")
    }
    .alert("ファイルを削除できませんでした", isPresented: deletionFailureBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.deletionFailureMessage ?? "")
    }
    .alert("保存できませんでした", isPresented: persistenceFailureBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.persistenceFailureMessage ?? "")
    }
    .alert("サンプルを削除しますか？", isPresented: $model.isSampleCleanupSuggested) {
      Button("削除", role: .destructive) {
        model.deleteSampleContent()
        model.completeSampleCleanupSuggestion()
      }
      Button("残す", role: .cancel) {
        model.completeSampleCleanupSuggestion()
      }
    } message: {
      Text("最初の記録を保存しました。表示用のサンプルが残っています。削除しますか？")
    }
    .sheet(item: $model.pendingCloudShare) { request in
      CloudShareSheet(share: request.share, container: request.container) {
        model.pendingCloudShare = nil
      }
    }
    .alert("チーム共有", isPresented: cloudShareMessageBinding) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.cloudShareMessage ?? "")
    }
    .alert("この端末の記録へのリンク", isPresented: missingRecordBinding) {
      if model.missingRecordNotice?.offersTrash == true {
        Button("最近削除した項目を見る") {
          model.missingRecordNotice = nil
          model.isRecentlyDeletedPresented = true
        }
      }
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.missingRecordNotice?.message ?? "")
    }
    .sheet(isPresented: $model.isRecentlyDeletedPresented) {
      NavigationStack {
        RecentlyDeletedView()
          .navigationTitle("最近削除した項目")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              ToolbarIconButton("完了", icon: .checkmark) { model.isRecentlyDeletedPresented = false }
            }
          }
      }
    }
  }

  private var missingRecordBinding: Binding<Bool> {
    Binding {
      model.missingRecordNotice != nil
    } set: { isPresented in
      if !isPresented {
        model.missingRecordNotice = nil
      }
    }
  }

  private var persistenceFailureBinding: Binding<Bool> {
    Binding {
      model.persistenceFailureMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.persistenceFailureMessage = nil
      }
    }
  }

  private var cloudShareMessageBinding: Binding<Bool> {
    Binding {
      model.cloudShareMessage != nil
    } set: { isPresented in
      if !isPresented { model.cloudShareMessage = nil }
    }
  }

  private var loadFailureBinding: Binding<Bool> {
    Binding {
      model.loadFailureMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.dismissLoadFailure()
      }
    }
  }

  private var deletionFailureBinding: Binding<Bool> {
    Binding {
      model.deletionFailureMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.deletionFailureMessage = nil
      }
    }
  }

  private var recordingErrorBinding: Binding<Bool> {
    Binding {
      model.recordingErrorMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.recordingErrorMessage = nil
      }
    }
  }

  private var importErrorBinding: Binding<Bool> {
    Binding {
      model.importErrorMessage != nil
    } set: { isPresented in
      if !isPresented {
        model.importErrorMessage = nil
      }
    }
  }

  private var pendingImportNoticeBinding: Binding<Bool> {
    Binding {
      model.pendingImportNotice != nil
    } set: { isPresented in
      if !isPresented {
        model.pendingImportNotice = nil
      }
    }
  }

  @ViewBuilder
  private var lockOverlay: some View {
    if appLock.isLocked {
      LockScreenView(onUnlock: {
        Task { await appLock.unlock() }
      }, authenticationMessage: appLock.authenticationMessage, isAuthenticating: appLock.isAuthenticating)
      .transition(.opacity)
    } else if appLock.isCovered {
      // A plain cover for the app switcher, without the unlock button.
      Color(uiColor: .systemBackground)
        .ignoresSafeArea()
    }
  }

  private var pendingInboxBinding: Binding<Bool> {
    Binding {
      model.pendingInboxCount != nil
    } set: { isPresented in
      if !isPresented {
        model.pendingInboxCount = nil
      }
    }
  }
}
