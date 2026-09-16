import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isComposing = false
  @State private var isSidebarOpen = false

  var body: some View {
    @Bindable var model = model

    SidebarContainer(isOpen: $isSidebarOpen, isEnabled: canRevealSidebar) {
      FileSidebarView(
        onSelectSection: selectFileSection,
        onSelectSpace: openSpace,
        onOpenSettings: openSettings,
        onClose: closeSidebar
      )
    } content: {
      mainSurface
    }
    .onChange(of: model.selectedTab) { _, _ in
      closeSidebar()
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

  private var mainSurface: some View {
    ZStack(alignment: .bottom) {
      tabSurface

      if model.isCaptureSourcePresented {
        // One full-bleed frost for the whole screen, tab bar included. It has
        // to ignore the safe areas or the status bar and the home indicator
        // stay sharp while everything between them blurs.
        Rectangle()
          .fill(.ultraThinMaterial)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture(perform: collapseCaptureMenu)
          .accessibilityLabel("作成メニューを閉じる")
          .accessibilityAddTraits(.isButton)
          .transition(.opacity)
      }

      if showsCaptureControl {
        CaptureControl()
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, 12)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: showsCaptureControl)
  }

  private var tabSurface: some View {
    @Bindable var model = model

    return TabView(selection: $model.selectedTab) {
      HomeView()
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
    // The composer keeps a clear gap from the tab bar so the two never read as
    // one stacked slab of controls.
    VStack(spacing: 18) {
      if let scope = composerScope, shouldShowComposer {
        QuickAIComposer(scope: scope, isComposing: $isComposing)
          .id(scope)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      if showsCaptureControl {
        MemoraBottomBar()
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .background(alignment: .bottom) {
      // Keeps scrolling content from peeking out under the home indicator.
      if showsBottomControls {
        Color(uiColor: .systemBackground)
          .frame(height: bottomStripHeight)
          .offset(y: bottomStripHeight)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: composerScope)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isComposing)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isDetailComposerVisible)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isBottomBarHidden)
  }

  /// The tab bar and the capture button appear and disappear together.
  private var showsCaptureControl: Bool {
    !isComposing && !isShowingMeetingDetail && !model.isBottomBarHidden
  }

  private var canRevealSidebar: Bool {
    model.selectedTab == .files
      && model.libraryPath.isEmpty
      && !model.isCaptureSourcePresented
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

  private func collapseCaptureMenu() {
    guard model.isCaptureSourcePresented else { return }
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
      model.isCaptureSourcePresented = false
    }
  }

  private let bottomStripHeight: CGFloat = 140

  private var composerScope: AIQueryScope? {
    if let meetingID = model.activeDetailMeetingID {
      return .file(meetingID)
    }
    if model.selectedTab == .askAI {
      return .global
    }
    guard model.selectedTab == .files else { return nil }
    guard let route = model.libraryPath.last else { return .global }
    if case .meeting(let meetingID) = route {
      return .file(meetingID)
    }
    if case .transcript(let meetingID) = route {
      return .file(meetingID)
    }
    return nil
  }

  private var shouldShowComposer: Bool {
    !isShowingMeetingDetail || model.isDetailComposerVisible
  }

  private var showsBottomControls: Bool {
    (composerScope != nil && shouldShowComposer) || (!isComposing && !isShowingMeetingDetail)
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
  /// Removes the system tab bar so `MemoraBottomBar` is the only bottom navigation.
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
