import SwiftUI

/// The top of Ask AI: Memora's mark and name in the middle, history on the
/// left, and search and a new chat on the right — the
/// new chat at the far edge, where it is easiest to reach again.
struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void
  var onWebResearch: () -> Void

  var body: some View {
    ZStack {
      HStack {
        headerButton("履歴", icon: .clockArrowCirclepath, action: onHistory)
          .memoraGlass(in: Circle(), interactive: true, backed: false)

        Spacer()

        HStack(spacing: 12) {
          Menu {
            Button("記録を検索", action: onSearch)
            Button("Web検索・Deep Research", action: onWebResearch)
          } label: {
            ToolbarIconGlyph(icon: .magnifyingglass).frame(width: 44, height: 44)
          }
          .accessibilityLabel("検索とWeb調査")
          .memoraGlass(in: Circle(), interactive: true, backed: false)
          headerButton("新しいチャット", icon: .squareAndPencil, action: onNewChat)
            .disabled(model.aiMessages.isEmpty)
            .memoraGlass(in: Circle(), interactive: true, backed: false)
        }
      }
      .padding(.horizontal, 20)
      .frame(maxHeight: .infinity, alignment: .top)

      VStack(spacing: -10) {
        ArtworkIcon(artwork: .askAIHeader, size: 36)
          .foregroundStyle(MemoraPalette.actionLabel)
          .frame(width: 64, height: 64)
          .background(
            MemoraPalette.action,
            in: Circle()
          )
        Text("Memora")
          .font(.headline)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .memoraGlass(in: Capsule())
      }
      .padding(.top, 4)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Memora")
      .accessibilityAddTraits(.isHeader)
    }
    .frame(height: 104)
  }

  private func headerButton(_ title: String, icon: MemoraIcon, action: @escaping () -> Void) -> some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      ToolbarIconGlyph(icon: icon)
        .font(.body.weight(.medium))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
