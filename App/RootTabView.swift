import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    @Bindable var model = model

    TabView(selection: $model.selectedTab) {
      LibraryView()
        .hidesSystemTabBar()
        .tag(RootTab.records)

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
    .safeAreaInset(edge: .bottom, spacing: 8) {
      VStack(spacing: 8) {
        if let scope = composerScope {
          QuickAIComposer(scope: scope)
        }

        MemoraBottomBar()
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .background {
        bottomScrim
      }
    }
    .sheet(isPresented: $model.isCaptureSourcePresented) {
      CaptureSourceSheet()
    }
  }

  /// Fades scrolling content out behind the bottom bar instead of letting rows
  /// show through the strip beneath it.
  private var bottomScrim: some View {
    LinearGradient(
      stops: [
        .init(color: Color(uiColor: .systemBackground).opacity(0), location: 0),
        .init(color: Color(uiColor: .systemBackground), location: 0.35)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea(edges: .bottom)
    .allowsHitTesting(false)
  }

  private var composerScope: AIQueryScope? {
    guard model.selectedTab == .records else { return nil }
    guard let route = model.libraryPath.last else { return .global }
    if case .meeting(let meetingID) = route {
      return .file(meetingID)
    }
    return nil
  }
}

private extension View {
  /// Removes the system tab bar so `MemoraBottomBar` is the only bottom navigation.
  /// The modifier has to be applied inside a tab, not on the `TabView` itself.
  func hidesSystemTabBar() -> some View {
    toolbar(.hidden, for: .tabBar)
      .toolbarBackgroundVisibility(.hidden, for: .tabBar)
  }
}
