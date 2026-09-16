import SwiftUI

/// The persistent tab bar. It deliberately stays below the screen-wide frost
/// that the capture menu puts up, so it blurs along with everything else
/// instead of needing a blur of its own.
struct MemoraBottomBar: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection

  var body: some View {
    MemoraGlassContainer(spacing: 14) {
      HStack(spacing: 10) {
        HStack(spacing: 0) {
          ForEach(RootTab.allCases) { tab in
            BottomTabButton(tab: tab, selection: selection)
          }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .memoraGlass(in: Capsule())

        // Holds the capture button's place. The button itself lives above the
        // frost, so it cannot be laid out in here.
        Color.clear
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
      }
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: model.selectedTab)
    .sensoryFeedback(.selection, trigger: model.selectedTab)
  }
}

private struct BottomTabButton: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var tab: RootTab
  var selection: Namespace.ID

  var body: some View {
    Button {
      guard model.selectedTab != tab else { return }
      withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
        model.selectedTab = tab
      }
    } label: {
      VStack(spacing: 2) {
        Image(systemName: tab.symbol)
          .font(.body.weight(.medium))
          .symbolRenderingMode(.monochrome)

        Text(tab.title)
          .font(.caption2.weight(isSelected ? .semibold : .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(maxWidth: .infinity, minHeight: 48)
      .background {
        if isSelected {
          BottomTabSelection(selection: selection)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var isSelected: Bool {
    model.selectedTab == tab
  }
}

private struct BottomTabSelection: View {
  var selection: Namespace.ID

  var body: some View {
    if #available(iOS 26.0, *) {
      Color.clear
        .glassEffect(.regular.tint(Color.primary.opacity(0.12)), in: Capsule())
        .glassEffectID("selectedTab", in: selection)
        .glassEffectTransition(.matchedGeometry)
    } else {
      Capsule()
        .fill(Color.primary.opacity(0.1))
        .matchedGeometryEffect(id: "selectedTab", in: selection)
    }
  }
}
