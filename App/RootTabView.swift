import SwiftUI

struct RootTabView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isComposing = false

  var body: some View {
    @Bindable var model = model

    TabView(selection: $model.selectedTab) {
      LibraryView()
        .hidesSystemTabBar()
        .scrollDismissesKeyboard(.immediately)
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
          QuickAIComposer(scope: scope, isComposing: $isComposing)
            .id(scope)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        // Typing gets the full screen; the bar comes back on dismiss.
        if !isComposing {
          MemoraBottomBar()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .background(alignment: .bottom) {
        // Content scrolls under the glass, but not into the home indicator
        // strip below it. The offset drops the fill just past the bar.
        Color(uiColor: .systemBackground)
          .frame(height: bottomStripHeight)
          .offset(y: bottomStripHeight)
      }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: composerScope)
      .animation(reduceMotion ? nil : MemoraMotion.control, value: isComposing)
    }
    .sheet(isPresented: $model.isCaptureSourcePresented) {
      CaptureSourceSheet()
    }
  }

  private let bottomStripHeight: CGFloat = 140

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
