import SwiftUI

struct SidebarHeaderView: View {
  var searchDestinationTitle: String
  var onSearch: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      SidebarBrandMark()
        .frame(minHeight: MemoraSpacing.touchTarget)
        .padding(.leading, MemoraSpacing.sm)

      Button {
        InteractionFeedback.shared.send(.tap)
        onSearch()
      } label: {
        HStack(spacing: MemoraSpacing.md) {
          MemoraInterfaceIcon(icon: .magnifyingglass)
          Text("\(searchDestinationTitle)を検索")
            .font(MemoraTypography.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemoraSpacing.sm)
        .padding(.vertical, MemoraSpacing.xs)
        .frame(minHeight: MemoraSpacing.touchTarget)
        .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: MemoraRadius.field))
        .contentShape(Rectangle())
      }
      .accessibilityIdentifier("sidebar.search")
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .foregroundStyle(MemoraPalette.textPrimary)
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.vertical, MemoraSpacing.md)
  }
}
