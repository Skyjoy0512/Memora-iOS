import SwiftUI

struct MemoraBottomBar: View {
  @Environment(MemoraModel.self) private var model
  @State private var addFeedback = 0

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 2) {
        BottomTabButton(tab: .records, title: "会議", symbol: "waveform")
        BottomTabButton(tab: .search, title: "Ask AI", symbol: "sparkles")
        BottomTabButton(tab: .tasks, title: "タスク", symbol: "checkmark.square")
        BottomTabButton(tab: .settings, title: "設定", symbol: "gearshape")
      }
      .padding(4)
      .frame(maxWidth: .infinity)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 0.5)
      }

      Button("追加", systemImage: "plus") {
        addFeedback += 1
        model.isCaptureSourcePresented = true
      }
      .labelStyle(.iconOnly)
      .font(.title3.weight(.semibold))
      .frame(width: 56, height: 56)
      .foregroundStyle(Color(uiColor: .systemBackground))
      .background(.primary, in: Circle())
      .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
      .sensoryFeedback(.impact(weight: .medium), trigger: addFeedback)
      .accessibilityHint("録音、音声インポート、オンライン会議から選びます")
    }
  }
}

private struct BottomTabButton: View {
  @Environment(MemoraModel.self) private var model
  var tab: RootTab
  var title: String
  var symbol: String

  var body: some View {
    Button {
      model.selectedTab = tab
    } label: {
      VStack(spacing: 3) {
        Image(systemName: symbol)
          .font(.body.weight(model.selectedTab == tab ? .semibold : .regular))
        Text(title)
          .font(.caption2.weight(model.selectedTab == tab ? .semibold : .regular))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(model.selectedTab == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(model.selectedTab == tab ? Color.primary.opacity(0.08) : .clear, in: Capsule())
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityAddTraits(model.selectedTab == tab ? .isSelected : [])
  }
}
