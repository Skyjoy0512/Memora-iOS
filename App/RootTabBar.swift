import LucideSwift
import SwiftUI

struct RootTabBar: View {
  @Binding var selection: RootTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let itemWidth: CGFloat = 64

  var body: some View {
    HStack(spacing: 0) {
      ForEach(RootTab.allCases) { tab in
        let isSelected = tab == selection
        Button {
          guard !isSelected else { return }
          InteractionFeedback.shared.send(.selection)
          selection = tab
        } label: {
          glyph(for: tab, isSelected: isSelected)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : MemoraMotion.control, value: isSelected)
            .accessibilityHidden(true)
            .frame(width: Self.itemWidth, height: MemoraSpacing.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("root.tab.\(tab.rawValue)")
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, MemoraSpacing.xs)
  }

  private func glyph(for tab: RootTab, isSelected: Bool) -> some View {
    let size = CGSize(width: 24, height: 24)
    return Image(lucide: tab.symbol.lucideName, size: size, style: isSelected ? .filled : .stroked)
      .foregroundStyle(isSelected ? MemoraPalette.textPrimary : MemoraPalette.textSecondary)
      .overlay(alignment: .top) {
        if tab == .home, isSelected {
          // Keep the separator legible inside the selected calendar silhouette.
          Capsule()
            .fill(MemoraPalette.background)
            .frame(width: 14, height: 1.5)
            .padding(.top, 8)
        }
      }
  }
}
