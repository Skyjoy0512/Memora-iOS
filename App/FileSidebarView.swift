import SwiftUI

struct FileSidebarView: View {
  @Environment(MemoraModel.self) private var model

  var onSearch: () -> Void
  var onOpenRecorder: () -> Void
  var onOpenProjects: () -> Void
  var onOpenDocuments: () -> Void
  var onOpenPeople: () -> Void
  var onSelectTab: (RootTab) -> Void
  var onOpenTools: () -> Void
  var onOpenSettings: () -> Void
  var onOpenAccount: () -> Void
  var onOpenPlan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SidebarHeaderView(
        searchDestinationTitle: searchDestinationTitle,
        onSearch: onSearch,
        onOpenProjects: onOpenProjects,
        onOpenDocuments: onOpenDocuments,
        onOpenPeople: onOpenPeople,
        onOpenRecorder: onOpenRecorder,
        onOpenAccount: onOpenAccount,
        onOpenPlan: onOpenPlan
      )

      ScrollView {
        VStack(spacing: 0) {
          SidebarRow(title: "ライブラリ", symbol: .folder,
            isSelected: !model.isToolsPresented && model.selectedTab == .library) {
            onSelectTab(.library)
          }
          SidebarRow(title: "ジャーナル", symbol: .calendar,
            isSelected: !model.isToolsPresented && model.selectedTab == .home) {
            onSelectTab(.home)
          }
          SidebarRow(title: "Ask AI", symbol: .sparkles,
            isSelected: !model.isToolsPresented && model.selectedTab == .askAI) {
            onSelectTab(.askAI)
          }
          SidebarRow(title: "マーケットプレイス", symbol: .bag, isSelected: model.isToolsPresented) {
            onOpenTools()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .accessibilityIdentifier("sidebar.navigation")
      }
      .scrollIndicators(.hidden)

      SidebarAccountFooter {
        InteractionFeedback.shared.send(.tap)
        onOpenSettings()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(MemoraPalette.secondaryBackground.ignoresSafeArea())
  }

  private var searchDestinationTitle: String {
    if model.isToolsPresented { return "マーケットプレイス" }
    if model.selectedTab == .library {
      if model.libraryPath == [.documents] { return "資料" }
      if model.libraryPath == [.people] { return "人物" }
      return model.librarySection.title
    }
    return model.selectedTab.title
  }
}

private struct SidebarRow: View {
  var title: LocalizedStringKey
  var symbol: MemoraIcon
  var isSelected = false
  var action: () -> Void

  var body: some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      HStack(spacing: MemoraSpacing.md) {
        MemoraInterfaceIcon(icon: symbol)
        Text(title)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(MemoraPalette.textPrimary)
      .padding(.vertical, MemoraSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .padding(.horizontal, MemoraSpacing.sm)
      .contentShape(Rectangle())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
