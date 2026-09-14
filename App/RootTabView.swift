import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isComposing = false

  var body: some View {
    @Bindable var model = model

    ZStack(alignment: .leading) {
      TabView(selection: $model.selectedTab) {
        LibraryView()
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

          if !isComposing && !isShowingMeetingDetail {
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
      }

      if model.isFileSidebarPresented {
        Color.black.opacity(0.16)
          .ignoresSafeArea()
          .onTapGesture {
            closeSidebar()
          }
          .transition(.opacity)

        FileSidebarView()
          .frame(maxWidth: min(332, UIScreen.main.bounds.width - 52))
          .transition(.move(edge: .leading).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.isFileSidebarPresented)
    .sheet(isPresented: $model.isCaptureSourcePresented) {
      CaptureSourceSheet()
    }
    .sheet(isPresented: $model.isFileCreationPresented) {
      FileCreationSheet()
    }
  }

  private func closeSidebar() {
    withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
      model.isFileSidebarPresented = false
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
