import SwiftUI

struct MemoraBottomBar: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selection
  @State private var addFeedback = 0

  var body: some View {
    MemoraGlassContainer(spacing: 18) {
      HStack(spacing: model.isBottomBarCompact ? 8 : 10) {
        HStack(spacing: 0) {
          BottomTabButton(tab: .files, title: "ファイル", symbol: "folder", selection: selection)
          BottomTabButton(tab: .lifeLog, title: "ライフログ", symbol: "waveform.path.ecg", selection: selection)
          BottomTabButton(tab: .search, title: "Ask AI", symbol: "sparkles", selection: selection)
          BottomTabButton(tab: .tasks, title: "タスク", symbol: "checklist", selection: selection)
          BottomTabButton(tab: .settings, title: "設定", symbol: "gearshape", selection: selection)
        }
        .padding(model.isBottomBarCompact ? 3 : 4)
        .frame(maxWidth: .infinity)
        .memoraGlass(in: Capsule())

        Button("追加", systemImage: "plus") {
          addFeedback += 1
          model.isCaptureSourcePresented = true
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .frame(
          width: model.isBottomBarCompact ? 48 : 56,
          height: model.isBottomBarCompact ? 48 : 56
        )
        .foregroundStyle(Color(uiColor: .systemBackground))
        .memoraGlass(in: Circle(), tint: .primary, interactive: true)
        .sensoryFeedback(.impact(weight: .medium), trigger: addFeedback)
        .accessibilityHint("録音、音声インポート、オンライン会議から選びます")
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.selectedTab)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: model.isBottomBarCompact)
    .sensoryFeedback(.selection, trigger: model.selectedTab)
  }
}

private struct BottomTabButton: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var tab: RootTab
  var title: String
  var symbol: String
  var selection: Namespace.ID

  var body: some View {
    Button {
      guard model.selectedTab != tab else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) {
        model.selectedTab = tab
      }
    } label: {
      Image(systemName: symbol)
        .font((model.isBottomBarCompact ? Font.subheadline : Font.body).weight(.medium))
        .symbolRenderingMode(.monochrome)
        .symbolEffect(.bounce, value: isSelected)
      .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(maxWidth: .infinity)
      .frame(height: model.isBottomBarCompact ? 36 : 44)
      .background {
        if isSelected {
          BottomTabSelection(selection: selection)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
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
      Capsule()
        .fill(Color.primary.opacity(0.035))
        .glassEffect(.regular.tint(Color.primary.opacity(0.12)), in: Capsule())
        .glassEffectID("selectedTab", in: selection)
    } else {
      Capsule()
        .fill(Color.primary.opacity(0.1))
        .matchedGeometryEffect(id: "selectedTab", in: selection)
    }
  }
}
