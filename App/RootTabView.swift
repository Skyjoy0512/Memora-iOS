import SwiftUI
import UIKit

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var isComposing = false
  @State private var isSidebarOpen = false
  @State private var isKeyboardVisible = false
  /// The full-bleed drawer hides the safe area from SwiftUI, so the floating
  /// controls re-add the home indicator inset themselves.
  @State private var safeAreaInsets = EdgeInsets()

  var body: some View {
    @Bindable var model = model

    SidebarContainer(isOpen: $isSidebarOpen, isEnabled: canRevealSidebar) {
      FileSidebarView(
        onSelectTab: selectTab,
        onSelectSection: selectFileSection,
        onSelectSpace: openSpace,
        onOpenSettings: openSettings,
        onClose: closeSidebar
      )
    } content: {
      tabSurface
    }
    .onChange(of: model.selectedTab) { _, _ in
      closeSidebar()
      // A screen that was scrolled when you left it should not hide the bar on
      // the next screen, and the capture popover belongs to the tab it opened on.
      model.isBottomBarHidden = false
      model.isCaptureSourcePresented = false
    }
    .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in refreshSafeAreaInsets() }
    .onChange(of: scenePhase) { _, _ in refreshSafeAreaInsets() }
    .onAppear { refreshSafeAreaInsets() }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      isKeyboardVisible = false
    }
    .sheet(isPresented: $model.isFileCreationPresented) {
      FileCreationSheet()
    }
    .sheet(isPresented: $model.isOnlineMeetingCapturePresented) {
      NavigationStack {
        OnlineMeetingCaptureView {
          model.isOnlineMeetingCapturePresented = false
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            await model.startCapture()
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("閉じる") {
              model.isOnlineMeetingCapturePresented = false
            }
          }
        }
      }
    }
  }

  private var tabSurface: some View {
    @Bindable var model = model

    return TabView(selection: $model.selectedTab) {
      HomeView(onOpenSidebar: openSidebar)
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.home)

      LibraryView(onOpenSidebar: openSidebar)
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.files)

      SearchView()
        .hidesSystemTabBar()
        .tag(RootTab.askAI)

      TasksView()
        .hidesSystemTabBar()
        .tag(RootTab.tasks)
    }
    .safeAreaInset(edge: .bottom, spacing: 8) {
      bottomControls
    }
    .accessibilityHidden(model.isCaptureSourcePresented)
    .background(Color(uiColor: .systemBackground))
  }

  private var bottomControls: some View {
    @Bindable var model = model

    // The composer keeps a clear gap from the tab bar so the two never read as
    // one stacked slab of controls.
    return VStack(spacing: 18) {
      // The composer retreats with the bar so the two never separate mid-scroll.
      if shouldShowComposer, !model.isBottomBarHidden {
        QuickAIComposer(
          scope: composerScope,
          isComposing: $isComposing,
          keepsFocusAfterSubmit: model.selectedTab == .askAI
        )
        .id(composerScope)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      if showsBottomBar {
        ProminentTabBar(
          selection: $model.selectedTab,
          isProminentPresented: $model.isCaptureSourcePresented,
          prominentSymbol: "plus"
        ) {
          CaptureMenuPopover()
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
    // `safeAreaInset` no longer contributes the home indicator inset inside the
    // full-bleed drawer, so add it back here — except while the keyboard is up,
    // where the keyboard's own safe area already lifts these controls.
    .padding(.bottom, isKeyboardVisible ? 14 : safeAreaInsets.bottom)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: composerScope)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isComposing)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isInlineEditing)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isDetailComposerVisible)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isBottomBarHidden)
  }

  private var showsBottomBar: Bool {
    !isComposing && !isShowingMeetingDetail && !model.isBottomBarHidden
  }

  private var canRevealSidebar: Bool {
    guard !model.isCaptureSourcePresented else { return false }
    switch model.selectedTab {
    case .home:
      return model.homePath.isEmpty
    case .files:
      return model.libraryPath.isEmpty
    default:
      return false
    }
  }

  private func openSidebar() {
    guard canRevealSidebar else { return }
    setSidebar(open: true)
  }

  private func closeSidebar() {
    guard isSidebarOpen else { return }
    setSidebar(open: false)
  }

  private func setSidebar(open: Bool) {
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
      isSidebarOpen = open
    }
  }

  private func refreshSafeAreaInsets() {
    let insets = WindowSafeArea.insets
    if insets != safeAreaInsets {
      safeAreaInsets = insets
    }
  }

  private func selectTab(_ tab: RootTab) {
    closeSidebar()
    guard model.selectedTab != tab else { return }
    withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
      model.selectedTab = tab
    }
  }

  private func selectFileSection(_ section: FileSection) {
    closeSidebar()
    withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
      model.selectedTab = .files
      model.fileSection = section
      model.libraryPath = []
    }
  }

  private func openSpace(_ space: MemoraSpace) {
    closeSidebar()
    model.selectedTab = .files
    model.fileSection = .projects
    model.libraryPath = [.space(space.id)]
  }

  private func openSettings() {
    closeSidebar()
    model.isSettingsPresented = true
  }

  /// Ask AI is available from every tab; only an open meeting narrows the scope.
  private var composerScope: AIQueryScope {
    if let meetingID = model.activeDetailMeetingID {
      return .file(meetingID)
    }
    guard model.selectedTab == .files, let route = model.libraryPath.last else {
      return .global
    }
    switch route {
    case .meeting(let meetingID), .transcript(let meetingID):
      return .file(meetingID)
    case .space(let spaceID):
      return .space(spaceID)
    default:
      return .global
    }
  }

  private var shouldShowComposer: Bool {
    // The Ask AI field steps aside while a document field holds the keyboard.
    !model.isInlineEditing && (!isShowingMeetingDetail || model.isDetailComposerVisible)
  }

  private var isShowingMeetingDetail: Bool {
    if model.activeDetailMeetingID != nil {
      return true
    }
    guard model.selectedTab == .files, let route = model.libraryPath.last else { return false }
    return switch route {
    case .meeting, .transcript:
      true
    default:
      false
    }
  }
}

private extension View {
  /// Removes the system tab bar so `ProminentTabBar` is the only bottom navigation.
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
