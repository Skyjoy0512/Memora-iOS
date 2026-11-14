import SwiftUI

struct SidebarHeaderView: View {
  var searchDestinationTitle: String
  var onSearch: () -> Void

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      SidebarBrandMark()
        .frame(minHeight: MemoraSpacing.touchTarget)
        .accessibilityLabel("Memora")

      Spacer(minLength: 0)

      Button {
        InteractionFeedback.shared.send(.tap)
        onSearch()
      } label: {
        Label("検索", icon: .magnifyingglass)
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
          .contentShape(Circle())
          .memoraGlass(in: Circle(), interactive: true)
      }
      .accessibilityHint("\(searchDestinationTitle)を検索します")
      .accessibilityIdentifier("sidebar.search")
    }
    .buttonStyle(.plain)
    .foregroundStyle(MemoraPalette.textPrimary)
    .padding(.leading, MemoraSpacing.section)
    .padding(.trailing, MemoraSpacing.screen)
    .padding(.vertical, MemoraSpacing.md)
  }
}
