import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isComposing = false
  @State private var showMenu = false
  @GestureState private var menuDragOffset: CGFloat = 0

  var body: some View {
    @Bindable var model = model

    GeometryReader { geometry in
      let menuWidth = min(340, geometry.size.width * 0.8)
      let contentOffset = resolvedMenuOffset(menuWidth: menuWidth)
      let progress = menuWidth > 0 ? contentOffset / menuWidth : 0

      ZStack(alignment: .leading) {
        if showMenu || menuDragOffset > 0 {
          FileSidebarView(
            onSelectSection: selectFileSection,
            onSelectTab: selectTab,
            onClose: closeSidebar
          )
          .frame(width: menuWidth)
          .offset(x: -menuWidth * 0.12 * (1 - progress))
          .opacity(0.62 + (0.38 * progress))
          .allowsHitTesting(showMenu)
          .transition(.opacity)
        }

        mainSurface
          .clipShape(
            RoundedRectangle(
              cornerRadius: progress > 0 ? 28 : 0,
              style: .continuous
            )
          )
          .scaleEffect(1 - (0.04 * progress), anchor: .trailing)
          .accessibilityHidden(showMenu)
          .overlay {
            if progress > 0 {
              Color.black.opacity(0.18 * progress)
                .contentShape(Rectangle())
                .onTapGesture(perform: closeSidebar)
                .allowsHitTesting(showMenu)
                .accessibilityLabel("メニューを閉じる")
                .accessibilityAddTraits(.isButton)
            }
          }
          .offset(x: contentOffset)
          .shadow(
            color: .black.opacity(0.16 * progress),
            radius: 24,
            x: -8
          )
      }
      .background(Color(uiColor: .systemBackground))
      .simultaneousGesture(sidebarGesture(menuWidth: menuWidth))
    }
    .animation(reduceMotion ? nil : .smooth, value: showMenu)
    .onChange(of: model.selectedTab) { _, _ in
      if showMenu {
        closeSidebar()
      }
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
    @Bindable var model = model

    return TabView(selection: $model.selectedTab) {
      LibraryView(onOpenSidebar: openSidebar)
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.files)

      LifeLogView()
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
        .tag(RootTab.lifeLog)

      SearchView()
        .hidesSystemTabBar()
        .tag(RootTab.search)

      TasksView()
        .hidesSystemTabBar()
        .tag(RootTab.tasks)

      SettingsView(showsCloseButton: false)
        .hidesSystemTabBar()
        .tag(RootTab.settings)
    }
    .safeAreaInset(edge: .bottom, spacing: 4) {
      VStack(spacing: 4) {
        if let scope = composerScope, shouldShowComposer {
          QuickAIComposer(scope: scope, isComposing: $isComposing)
            .id(scope)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if !isComposing && !isShowingMeetingDetail && !model.isBottomBarHidden {
          MemoraBottomBar()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 4)
      .background(alignment: .bottom) {
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
    .background(Color(uiColor: .systemBackground))
  }

  private func resolvedMenuOffset(menuWidth: CGFloat) -> CGFloat {
    let restingOffset = showMenu ? menuWidth : 0
    return min(max(restingOffset + menuDragOffset, 0), menuWidth)
  }

  private func sidebarGesture(menuWidth: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 10, coordinateSpace: .global)
      .updating($menuDragOffset) { value, state, _ in
        guard showMenu || canRevealSidebar && value.startLocation.x <= 28 else { return }
        state = showMenu
          ? min(0, max(-menuWidth, value.translation.width))
          : max(0, min(menuWidth, value.translation.width))
      }
      .onEnded { value in
        guard showMenu || canRevealSidebar && value.startLocation.x <= 28 else { return }
        let restingOffset = showMenu ? menuWidth : 0
        let projectedOffset = min(
          max(restingOffset + value.predictedEndTranslation.width, 0),
          menuWidth
        )
        withAnimation(reduceMotion ? nil : .smooth) {
          showMenu = projectedOffset > menuWidth * 0.5
        }
      }
  }

  private var canRevealSidebar: Bool {
    model.selectedTab == .files
      && model.libraryPath.isEmpty
  }

  private func openSidebar() {
    guard canRevealSidebar else { return }
    withAnimation(reduceMotion ? nil : .smooth) {
      showMenu = true
    }
  }

  private func closeSidebar() {
    withAnimation(reduceMotion ? nil : .smooth) {
      showMenu = false
    }
  }

  private func selectFileSection(_ section: FileSection) {
    withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
      model.selectedTab = .files
      model.fileSection = section
      model.libraryPath = []
      showMenu = false
    }
  }

  private func selectTab(_ tab: RootTab) {
    withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
      model.selectedTab = tab
      showMenu = false
    }
  }

  private let bottomStripHeight: CGFloat = 140

  private var composerScope: AIQueryScope? {
    if let meetingID = model.activeDetailMeetingID {
      return .file(meetingID)
    }
    if model.selectedTab == .search {
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
