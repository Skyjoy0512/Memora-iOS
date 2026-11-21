import SwiftUI
import UIKit
import EventKit
import UniformTypeIdentifiers
import PhotosUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var isComposing = false
  @State private var isSidebarOpen = false
  @State private var pendingSidebarAction: (() -> Void)?
  @State private var isKeyboardVisible = false
  @State private var isCaptureMenuPresented = false
  @State private var isCaptureFileImporterPresented = false
  @State private var captureImportContext: LocalImportContext?
  @State private var captureMenuContext: LocalImportContext?
  @State private var pendingCaptureMenuAction: CaptureSheetAction?
  @State private var captureFileTypes: [UTType] = [.audio]
  @State private var isCapturePhotosPresented = false
  @State private var capturePhotos: [PhotosPickerItem] = []
  @State private var capturePhotoContext: LocalImportContext?
  @State private var isCameraPresented = false
  @State private var cameraContext: LocalImportContext?
  @State private var cameraPhoto: Data?
  @State private var isCaptureMediaImporting = false
  @State private var onlineMeetingContext: LocalImportContext?
  @State private var shouldStartOnlineMeeting = false
  /// The full-bleed drawer hides the safe area from SwiftUI, so the floating
  /// controls re-add the home indicator inset themselves.
  @State private var safeAreaInsets = EdgeInsets()

  var body: some View {
    @Bindable var model = model

    SidebarContainer(isOpen: $isSidebarOpen, isEnabled: canRevealSidebar,
      onCloseAnimationCompleted: completeSidebarAction) {
      FileSidebarView(
        onSearch: { closeSidebar { model.sidebarSearchRequest = UUID() } },
        onOpenDocuments: openDocuments,
        onOpenPeople: openPeople,
        onOpenTasks: openTasks,
        onOpenTools: {
          selectFromSidebar { model.isToolsPresented = true }
        },
        onOpenSettings: openSettings
      )
    } content: {
      GeometryReader { geometry in
        ZStack {
          // Keep navigation mounted, but move its UIKit-backed views outside
          // the viewport so they cannot cover or expose controls under Tools.
          tabSurface
            .offset(x: model.isToolsPresented ? -geometry.size.width : 0)
            .opacity(model.isToolsPresented ? 0 : 1)
            .allowsHitTesting(!model.isToolsPresented)
            .accessibilityHidden(model.isToolsPresented)
          if model.isToolsPresented {
            NavigationStack {
              ToolsView(onOpenSidebar: openSidebar, onClose: { model.isToolsPresented = false })
            }
              .transition(.identity)
              .zIndex(1)
          }
        }
      }
    }
    .environment(\.revealMemoraSidebar, MemoraSidebarAction(id: ObjectIdentifier(model), action: openSidebar))
    .onChange(of: model.isToolsPresented) { _, isOpen in
      if isOpen {
        model.composerDismissRequests += 1
        dismissCaptureMenu()
      }
    }
    .onChange(of: model.isSearchActive) { _, isSearching in
      if isSearching { dismissCaptureMenu() }
    }
    .onChange(of: isComposing) { _, composing in
      if composing { dismissCaptureMenu() }
    }
    .onChange(of: model.registeredLLMs.revision) { _, _ in
      model.interruptPendingSummaries(requiresUserRetry: true)
    }
    .onChange(of: isSidebarOpen) { _, open in
      if open { model.composerDismissRequests += 1 }
    }
    .onChange(of: model.selectedTab) { _, _ in
      closeSidebar()
      // The composer belongs to the screen that was left; a new tab starts with
      // its content visible rather than behind a keyboard carried over.
      model.composerDismissRequests += 1
      // The capture popover belongs to the screen it opened on.
      model.isCaptureSourcePresented = false
      dismissCaptureMenu()
      // A search belongs to the tab it was opened on.
      model.isSearchActive = false
    }
    .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in refreshSafeAreaInsets() }
    .onChange(of: scenePhase) { _, phase in
      model.updateRecordingResources(isForeground: phase == .active)
      refreshSafeAreaInsets()
      // Automatic records written while the app was away land when it returns.
      if phase == .active {
        model.invalidateAICalendarContext()
        model.importAutoLifeLogInbox()
        model.prepareWeeklyReviewIfNeeded()
        Task { await model.refreshShareInbox() }
        Task { await model.runDueResidents() }
        model.scanInboxForAudio()
        AutoLocationLogger.shared.startIfEnabled()
        // A permission request left unanswered when the app went away is
        // resolved here so the toggle does not hang.
        AutoLocationLogger.shared.resolvePendingEnableOnActivation()
      } else {
        // Leaving the foreground while the "always" prompt is requested is what
        // shows the prompt really appeared.
        AutoLocationLogger.shared.handleSceneInactive()
        // Wakes the app for the next resident run while it is away.
        if phase == .background {
          model.persistActiveAIConversation()
          model.scheduleResidentRefresh()
        }
      }
    }
    .onAppear {
      model.updateRecordingResources(isForeground: scenePhase == .active)
      refreshSafeAreaInsets()
      model.prepareWeeklyReviewIfNeeded()
    }
    .task { await model.refreshShareInbox() }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      model.refreshRecordingResources()
    }
    .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
      model.refreshRecordingResources()
    }
    .task { await model.refreshTeams() }
    .onChange(of: model.spaces) { _, _ in Task { await model.refreshShareInbox() } }
    .onChange(of: model.currentTeamID) { _, _ in Task { await model.refreshShareInbox() } }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      isKeyboardVisible = false
    }
    .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main)) { _ in
      model.invalidateAICalendarContext()
    }
    .fileImporter(isPresented: $isCaptureFileImporterPresented, allowedContentTypes: captureFileTypes) { result in
      let context = captureImportContext
      captureImportContext = nil
      switch result {
      case .success(let url):
        Task { await model.importInformationFile(url, context: context) }
      case .failure(let error):
        guard (error as NSError).code != NSUserCancelledError else { return }
        model.importErrorMessage = "ファイルを選択できませんでした。もう一度お試しください。"
      }
    }
    .sheet(isPresented: $isCaptureMenuPresented, onDismiss: completeCaptureMenuDismissal) {
      CaptureMenuSheet(onSelect: selectCaptureMenuItem)
    }
    .photosPicker(isPresented: $isCapturePhotosPresented, selection: $capturePhotos, maxSelectionCount: 6, matching: .images)
    .onChange(of: capturePhotos) { _, photos in
      guard !photos.isEmpty else { return }
      let context = capturePhotoContext
      capturePhotoContext = nil
      capturePhotos = []
      if let context {
        isCaptureMediaImporting = true
        Task {
          defer { isCaptureMediaImporting = false }
          await model.importCapturePhotos(photos, context: context)
        }
      }
    }
    .fullScreenCover(isPresented: $isCameraPresented, onDismiss: completeCameraDismissal) {
      CameraCaptureView { photo in
        guard cameraContext?.isCurrent(in: model) == true else {
          model.importErrorMessage = "保存先が変更されたため、撮影した資料を追加できませんでした。保存先を開き直して再試行してください。"
          isCameraPresented = false
          return
        }
        cameraPhoto = photo
        isCameraPresented = false
      }
    }
    .onChange(of: model.aiWorkspaceGeneration) { _, _ in
      dismissCaptureMenu()
      isCameraPresented = false
      cameraContext = nil
      cameraPhoto = nil
      isCapturePhotosPresented = false
      capturePhotoContext = nil
      capturePhotos = []
      isCaptureFileImporterPresented = false
      captureImportContext = nil
    }
    .sheet(isPresented: Binding(get: { model.isSourceAddPresented || model.sourceAddProjectID != nil }, set: { if !$0 { model.sourceAddProjectID = nil; model.isSourceAddPresented = false; model.sourceAddAsMemo = false } })) {
      ProjectSourceAddSheet(projectID: model.sourceAddProjectID, isMemo: model.sourceAddAsMemo)
    }
    .sheet(isPresented: $model.isFileCreationPresented) {
      FileCreationSheet()
    }
    .sheet(isPresented: $model.isLifeLogCreationPresented, onDismiss: { model.lifeLogCreationDate = nil }) {
      LifeLogCreationSheet(date: model.lifeLogCreationDate ?? .now, eventDate: model.lifeLogCreationDate)
    }
    .sheet(isPresented: $model.isRecorderConnectionPresented) {
      NavigationStack {
        ExternalRecorderSettingsView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              ToolbarIconButton("完了", icon: .checkmark) { model.isRecorderConnectionPresented = false }
            }
          }
      }
    }
    .sheet(isPresented: $model.isCallSetupPresented) {
      CallSetupFlow()
    }
    .sheet(isPresented: $model.isDialerPresented) {
      DialerView()
    }
    .fullScreenCover(item: $model.activeCall) { session in
      ActiveCallView(session: session) {
        model.saveEndedCall(session)
      }
    }
    .sheet(isPresented: $model.isTeamCreationPresented) {
      TeamCreateSheet()
    }
    .sheet(isPresented: $model.isTeamJoinPresented) {
      TeamJoinSheet()
    }
    .sheet(item: $model.pendingMailDraft) { draft in
      MailDraftSheet(draft: draft) { model.pendingMailDraft = nil }
    }
    .sheet(item: $model.pendingSourceCitation) { target in
      ArtifactSourceDetailView(target: target, workspaceID: nil)
    }
    .sheet(isPresented: $model.isOnlineMeetingCapturePresented, onDismiss: completeOnlineMeetingDismissal) {
      NavigationStack {
        OnlineMeetingCaptureView {
          shouldStartOnlineMeeting = true
          model.isOnlineMeetingCapturePresented = false
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) {
              model.isOnlineMeetingCapturePresented = false
            }
          }
        }
      }
      .onAppear {
        shouldStartOnlineMeeting = false
        onlineMeetingContext = LocalImportContext(projectID: model.onlineMeetingCaptureSpaceID, in: model)
      }
    }
    .overlay(alignment: .bottom) {
      if let undo = model.pendingUndo {
        UndoToast(action: undo)
          .id(undo.id)
          .padding(.horizontal, 12)
          .padding(.bottom, max(model.bottomControlsHeight, 24) + tabBarClearance + 8)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.pendingUndo?.id)
  }

  private func completeOnlineMeetingDismissal() {
    let event = model.onlineMeetingCaptureEvent
    let spaceID = model.onlineMeetingCaptureSpaceID
    let context = onlineMeetingContext
    let shouldStart = shouldStartOnlineMeeting
    model.onlineMeetingCaptureEvent = nil
    model.onlineMeetingCaptureSpaceID = nil
    onlineMeetingContext = nil
    shouldStartOnlineMeeting = false
    guard shouldStart else { return }
    guard let context else {
      model.recordingErrorMessage = "この保存先では録音できません。画面を開き直してください。"
      return
    }
    // Wait for the system's dismissal, rather than guessing its animation time.
    Task { await model.startCapture(event: event, spaceID: spaceID, context: context) }
  }

  private var tabSurface: some View {
    @Bindable var model = model
    return VStack(spacing: 0) {
      TabView(selection: $model.selectedTab) {
        rootTab(.library) { LibraryView(onOpenSidebar: openSidebar).scrollDismissesKeyboard(.immediately) }
        rootTab(.home) { HomeView(onOpenSidebar: openSidebar).scrollDismissesKeyboard(.immediately) }
        rootTab(.askAI) { SearchView(isComposing: isComposing, onOpenSidebar: openSidebar) }
      }
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottom) {
        bottomControls.allowsHitTesting(shouldShowComposer || showsPlaybackBar)
      }

      if showsPrimaryTabs {
        RootTabBar(selection: $model.selectedTab)
          .padding(.bottom, safeAreaInsets.bottom)
          .background(MemoraPalette.background)
      }
    }
    .accessibilityHidden(model.isCaptureSourcePresented)
    .background(Color(uiColor: .systemBackground))
  }

  private func rootTab<Content: View>(_ tab: RootTab, @ViewBuilder content: () -> Content) -> some TabContent<RootTab> {
    Tab(value: tab) {
      content()
        .toolbar(.hidden, for: .tabBar)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
    } label: {
      Text(tab.title)
    }
  }

  private var tabBarClearance: CGFloat {
    showsPrimaryTabs ? RootTabBar.height + safeAreaInsets.bottom : 0
  }

  private var showsPrimaryTabs: Bool {
    RootNavigation.showsPrimaryTabs(in: model.activeNavigationPath)
      && !isSearchCovering && !isComposing && !isKeyboardVisible && !model.isInlineEditing
      && !isShowingMeetingDetail && !model.isToolsPresented
  }

  private var bottomControls: some View {
    @Bindable var model = model

    // A small gap keeps the composer and the bar reading as one block.
    return VStack(spacing: 12) {
      // The recording's transport rides above the composer, on the same floating
      // layer, so it never overlaps the composer or the home indicator.
      if showsPlaybackBar, let player = model.activePlayback {
        MeetingPlaybackBar(player: player)
          .padding(.horizontal, 12)
          .transition(
            reduceMotion
              ? .opacity
              : .move(edge: .bottom).combined(with: .opacity)
          )
      }

      // These controls are independent surfaces. A shared glass container can
      // intercept native menu rows where they overlap the composer's surface.
      Group {
        HStack(alignment: .bottom, spacing: 0) {
          if shouldShowComposer {
            QuickAIComposer(
              scope: composerScope,
              isComposing: $isComposing,
              keepsFocusAfterSubmit: model.selectedTab == .askAI || model.activeProjectChatID != nil,
              compactIdle: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, showsCaptureButtons ? 60 : 0)
            // Keep the editor identity while the available width changes.
            .transition(.opacity)
          }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth)
        .overlay(alignment: .bottomTrailing) {
          CaptureFloatingButtons(spaceID: model.visibleProjectID, isVisible: showsCaptureButtons,
            includesProjectCreation: model.selectedTab == .library && model.librarySection == .projects,
            onOpenCaptureMenu: presentCaptureMenu)
            .allowsHitTesting(showsCaptureButtons)
            .accessibilityHidden(!showsCaptureButtons)
            .disabled(isCaptureMediaImporting)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
      }

    }
    .padding(.top, 4)
    // The tab row reserves the home inset whenever it is visible.
    .padding(.bottom, showsPrimaryTabs ? MemoraSpacing.xs : (isKeyboardVisible ? 14 : safeAreaInsets.bottom))
    .background {
      if shouldShowComposer {
        ComposerBackdrop()
          .containerRelativeFrame(.horizontal)
          .padding(.top, -32)
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
      if abs(model.bottomControlsHeight - height) > 0.5 {
        model.bottomControlsHeight = height
      }
    }
    .animation(reduceMotion || model.selectedTab == .askAI ? nil : MemoraMotion.control, value: isComposing)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.activePlayback != nil)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isInlineEditing)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isDetailComposerVisible)
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: shouldShowComposer)
    // Leaving or opening a record moves the bar with the screen, rather than
    // letting it snap in or out.
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: isShowingMeetingDetail)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isCaptureSourcePresented)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isSearchCovering)
  }

  private var showsCaptureButtons: Bool {
    guard model.selectedTab != .askAI, shouldShowComposer, !isComposing, !isKeyboardVisible, !isShowingMeetingDetail else { return false }
    return RootNavigation.offersCapture(tab: model.selectedTab, path: model.activeNavigationPath)
  }

  /// An open search, or picking files, takes the screen until a record is
  /// opened on top of it.
  private var isSearchCovering: Bool {
    RootNavigation.searchCoversScreen(tab: model.selectedTab, path: model.activeNavigationPath,
      isSearching: model.isSearchActive, isSelectingFiles: model.isFileSelectionActive)
  }

  /// The transport only appears while a detail is playing and no field (the
  /// composer or an inline editor) owns the keyboard.
  private var showsPlaybackBar: Bool {
    model.activePlayback != nil && !isComposing && !isKeyboardVisible && !model.isInlineEditing
  }

  private var canRevealSidebar: Bool {
    guard !model.isToolsPresented, !model.isCaptureSourcePresented, !isCaptureMenuPresented,
          !model.isSearchActive else { return false }
    switch model.selectedTab {
    case .home:
      return model.homePath.isEmpty
    case .library:
      return model.libraryPath.isEmpty
    case .askAI:
      return true
    }
  }

  private func presentCaptureMenu() {
    guard !isCaptureMenuPresented, !model.isImporting, !isCaptureMediaImporting,
          let context = LocalImportContext(projectID: model.visibleProjectID, in: model) else { return }
    InteractionFeedback.shared.send(.tap)
    pendingCaptureMenuAction = nil
    captureMenuContext = context
    isCaptureMenuPresented = true
  }

  private func dismissCaptureMenu() {
    pendingCaptureMenuAction = nil
    isCaptureMenuPresented = false
  }

  private func selectCaptureMenuItem(_ action: CaptureSheetAction) {
    guard isCaptureMenuPresented, pendingCaptureMenuAction == nil else { return }
    pendingCaptureMenuAction = action
    isCaptureMenuPresented = false
  }

  /// A picker or the recorder may present another sheet; wait for the system's
  /// dismissal callback rather than racing its transition with a fixed delay.
  private func completeCaptureMenuDismissal() {
    guard !isCaptureMenuPresented else { return }
    let action = pendingCaptureMenuAction
    let context = captureMenuContext
    pendingCaptureMenuAction = nil
    captureMenuContext = nil
    guard let action else { return }
    guard let context, context.isCurrent(in: model) else {
      model.importErrorMessage = "保存先が変更されました。画面を開き直してお試しください。"
      return
    }
    switch action {
    case .importAudio, .files:
      captureImportContext = context
      captureFileTypes = action == .importAudio ? [.audio] : [.data]
      isCaptureFileImporterPresented = true
    case .recording:
      Task { await model.startCapture(spaceID: context.projectID, context: context) }
    case .onlineMeeting:
      Task {
        guard context.isCurrent(in: model) else { return }
        await model.performCaptureMenuAction(.onlineMeeting, projectID: context.projectID)
      }
    case .newNote, .link:
      model.sourceAddProjectID = context.projectID
      model.sourceAddAsMemo = action == .newNote
      model.isSourceAddPresented = true
    case .photos:
      capturePhotoContext = context
      isCapturePhotosPresented = true
    case .camera:
      cameraContext = context
      cameraPhoto = nil
      isCameraPresented = true
    }
  }

  private func completeCameraDismissal() {
    let photo = cameraPhoto, context = cameraContext
    cameraPhoto = nil
    cameraContext = nil
    guard let photo, let context, context.isCurrent(in: model) else { return }
    isCaptureMediaImporting = true
    Task {
      defer { isCaptureMediaImporting = false }
      await model.importCameraPhoto(photo, context: context)
    }
  }

  private func openSidebar() {
    guard canRevealSidebar || model.isToolsPresented else { return }
    pendingSidebarAction = nil
    setSidebar(open: true)
  }

  private func closeSidebar() {
    guard isSidebarOpen else { return }
    setSidebar(open: false)
  }

  private func closeSidebar(completion: @escaping () -> Void) {
    guard isSidebarOpen else { completion(); return }
    // The tab surface contains unrelated animations. Wait only for the drawer's
    // own transform, not for every animation in a presentation transaction.
    pendingSidebarAction = completion
    setSidebar(open: false)
  }

  private func completeSidebarAction() {
    guard !isSidebarOpen, let action = pendingSidebarAction else { return }
    pendingSidebarAction = nil
    action()
  }

  private func selectFromSidebar(_ update: () -> Void) {
    // Do not let a pushed route or the composer's own animations compete with
    // the full-screen drawer closing over the newly selected destination.
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      model.composerDismissRequests += 1
      model.isSearchActive = false
      update()
    }
    closeSidebar()
  }

  private func setSidebar(open: Bool) {
    withAnimation(reduceMotion ? nil : MemoraMotion.drawer) {
      isSidebarOpen = open
    }
  }

  private func refreshSafeAreaInsets() {
    let insets = WindowSafeArea.insets
    if insets != safeAreaInsets {
      safeAreaInsets = insets
    }
  }

  private func openDocuments() {
    selectFromSidebar {
      model.isToolsPresented = false
      model.selectedTab = .library
      model.libraryPath = [.documents]
    }
  }

  private func openPeople() {
    selectFromSidebar {
      model.isToolsPresented = false
      model.selectedTab = .library
      model.libraryPath = [.people]
    }
  }

  private func openTasks() {
    selectFromSidebar {
      model.isToolsPresented = false
      model.selectedTab = .home
      model.homePath = [.tasks]
    }
  }

  private func openSettings() {
    closeSidebar { model.isSettingsPresented = true }
  }

  private var composerScope: AIQueryScope {
    if let id = model.activeProjectChatID, let projectID = model.projectChat(id: id)?.projectID,
       model.space(id: projectID) != nil { return .space(projectID) }
    if case .projectSource(let id) = model.activeNavigationPath.last,
       let projectID = model.source(id: id)?.projectID, model.space(id: projectID) != nil { return .space(projectID) }
    if case .projectPDF(let id, _) = model.activeNavigationPath.last,
       let projectID = model.source(id: id)?.projectID, model.space(id: projectID) != nil { return .space(projectID) }
    return RootNavigation.scope(tab: model.selectedTab, path: model.activeNavigationPath,
      detailMeetingID: model.activeDetailMeetingID, detailTab: model.activeDetailTabs.last)
  }

  private var shouldShowComposer: Bool {
    guard !model.isToolsPresented, !model.isInlineEditing, !isSearchCovering else { return false }
    if case .projectChat(let id) = model.activeNavigationPath.last {
      guard let projectID = model.projectChat(id: id)?.projectID, model.space(id: projectID) != nil else { return false }
    }
    // Record detail must explicitly make room for its contextual composer.
    if isShowingMeetingDetail {
      return model.isDetailComposerVisible
    }
    // Every list tab, including Ask AI, uses the shared input above the bar.
    return true
  }

  private var isShowingMeetingDetail: Bool {
    if case .file = composerScope { return true }
    return false
  }
}
