import SwiftUI

struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void

  var body: some View {
    HStack {
      headerButton("メニュー", icon: .line3Horizontal, action: onOpenSidebar)
        .memoraGlass(in: Circle(), interactive: true, backed: false)
      Spacer()
      Menu {
        if model.aiPersonScopeID != nil {
          Button("すべての記録の新しいチャット", icon: .squareAndPencil) { model.startNewAIChat() }
        }
        Button("履歴", icon: .clockArrowCirclepath, action: onHistory)
        Button("検索", icon: .magnifyingglass, action: onSearch)
      } label: {
        Text(model.aiPersonScopeID.flatMap { model.person(id: $0)?.name } ?? "Memora")
          .font(.headline)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Memora、履歴と検索")
      Spacer()
      headerButton("新しいチャット", icon: .squareAndPencil, action: onNewChat)
        .disabled(model.aiMessages.isEmpty)
        .memoraGlass(in: Circle(), interactive: true, backed: false)
    }
    .padding(.horizontal, MemoraSpacing.xl)
    .frame(minHeight: 48)
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
