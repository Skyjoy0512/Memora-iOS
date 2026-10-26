import SwiftUI
import UIKit
import EventKit

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var isComposing = false
  @State private var isSidebarOpen = false
  @State private var pendingSidebarAction: (() -> Void)?
  @State private var isKeyboardVisible = false
  /// The full-bleed drawer hides the safe area from SwiftUI, so the floating
  /// controls re-add the home indicator inset themselves.
  @State private var safeAreaInsets = EdgeInsets()

  var body: some View {
    @Bindable var model = model

    SidebarContainer(isOpen: $isSidebarOpen, isEnabled: canRevealSidebar,
      onCloseAnimationCompleted: completeSidebarAction) {
      FileSidebarView(
        onSearch: { closeSidebar { model.sidebarSearchRequest = UUID() } },
        onOpenRecorder: {
          closeSidebar { model.isRecorderConnectionPresented = true }
        },
        onOpenProjects: {
          selectFromSidebar {
            model.isToolsPresented = false
            model.openProjects()
          }
        },
        onOpenDocuments: openDocuments,
        onOpenPeople: openPeople,
        onSelectTab: { tab in
          selectFromSidebar {
            model.isToolsPresented = false
            model.selectedTab = tab
          }
        },
        onOpenTools: {
          selectFromSidebar { model.isToolsPresented = true }
        },
        onOpenSettings: openSettings,
        onOpenAccount: {
          closeSidebar {
            if !model.isSignedIn { model.isAuthPresented = true }
          }
        },
        onOpenPlan: {
          closeSidebar { model.isPaywallPresented = true }
        }
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
            NavigationStack { ToolsView(onOpenSidebar: openSidebar) }
              .transition(.identity)
              .zIndex(1)
          }
        }
      }
    }
    .onChange(of: model.isToolsPresented) { _, isOpen in
      if isOpen { model.composerDismissRequests += 1 }
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
    .sheet(isPresented: Binding(get: { model.sourceAddProjectID != nil }, set: { if !$0 { model.sourceAddProjectID = nil } })) {
      if let id = model.sourceAddProjectID { ProjectSourceAddSheet(projectID: id) }
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
    .sheet(isPresented: $model.isOnlineMeetingCapturePresented, onDismiss: {
      model.onlineMeetingCaptureEvent = nil
      model.onlineMeetingCaptureSpaceID = nil
    }) {
      NavigationStack {
        OnlineMeetingCaptureView {
          let event = model.onlineMeetingCaptureEvent
          let spaceID = model.onlineMeetingCaptureSpaceID
          model.isOnlineMeetingCapturePresented = false
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await model.startCapture(event: event, spaceID: spaceID)
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) {
              model.isOnlineMeetingCapturePresented = false
            }
          }
        }
      }
    }
    .overlay(alignment: .bottom) {
      if let undo = model.pendingUndo {
        UndoToast(action: undo)
          .id(undo.id)
          .padding(.horizontal, 12)
          .padding(.bottom, max(model.bottomControlsHeight, 24) + 8)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.pendingUndo?.id)
  }

  private var tabSurface: some View {
    @Bindable var model = model

    return TabView(selection: $model.selectedTab) {
      LibraryView(onOpenSidebar: openSidebar)
        .accessibilityHidden(model.isToolsPresented || isSidebarOpen)
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.library)

      HomeView(onOpenSidebar: openSidebar)
        .accessibilityHidden(model.isToolsPresented || isSidebarOpen)
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.home)

      SearchView(onOpenSidebar: openSidebar)
        .accessibilityHidden(model.isToolsPresented || isSidebarOpen)
        .hidesSystemTabBar()
        .tag(RootTab.askAI)
    }
    .safeAreaInset(edge: .bottom, spacing: 8) {
      bottomControls
    }
    .accessibilityHidden(model.isCaptureSourcePresented)
    .background(Color(uiColor: .systemBackground))
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

      // Scrolling hides only the tab bar; Ask AI stays at the bottom so it is
      // always one tap away.
      if shouldShowComposer {
        QuickAIComposer(
          scope: composerScope,
          isComposing: $isComposing,
          keepsFocusAfterSubmit: model.selectedTab == .askAI || model.activeProjectChatID != nil
        )
        // The Ask AI component keeps a small side margin on every page.
        .containerRelativeFrame(.horizontal) { width, _ in
          min(width * 0.945, MemoraSpacing.readingWidth)
        }
        // Note: no `.id(composerScope)` — recreating the field would throw away
        // what someone had already typed when the scope changed.
        // A glass-like entrance: it blurs and rises into place instead of
        // snapping in.
        .transition(
          reduceMotion
            ? .opacity
            : .move(edge: .bottom)
              .combined(with: .opacity)
              .combined(with: .scale(scale: 0.94, anchor: .bottom))
        )
      }

    }
    .padding(.top, 4)
    // `safeAreaInset` no longer contributes the home indicator inset inside the
    // full-bleed drawer, so add it back here — except while the keyboard is up,
    // where the keyboard's own safe area already lifts these controls.
    .padding(.bottom, isKeyboardVisible ? 14 : safeAreaInsets.bottom)
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
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isComposing)
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
    guard !model.isToolsPresented, !model.isCaptureSourcePresented, !model.isSearchActive else { return false }
    switch model.selectedTab {
    case .home:
      return model.homePath.isEmpty
    case .library:
      return model.libraryPath.isEmpty
    case .askAI:
      return true
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
    withTransaction(transaction, update)
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
      model.librarySection = .files
      model.libraryPath = [.documents]
    }
  }

  private func openPeople() {
    selectFromSidebar {
      model.isToolsPresented = false
      model.selectedTab = .library
      model.librarySection = .files
      model.libraryPath = [.people]
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
    // The detail keeps its own contextual field; Ask AI has its own chat field,
    // so the shared "Ask Anything" bar is for the three list tabs.
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

private extension View {
  /// Removes the system tab bar: navigation lives in the side menu, and the
  /// bottom edge belongs to the Ask AI composer.
  /// The modifier has to be applied inside a tab, not on the `TabView` itself.
  @ViewBuilder
  func hidesSystemTabBar() -> some View {
    let base = toolbar(.hidden, for: .tabBar)
      .toolbarBackgroundVisibility(.hidden, for: .tabBar)

    if #available(iOS 26.0, *) {
      // Blurs scrolling content as it passes under the floating bar, so the
      // glass stays legible.
      base.scrollEdgeEffectStyle(.hard, for: .bottom)
    } else {
      base
    }
  }
}
