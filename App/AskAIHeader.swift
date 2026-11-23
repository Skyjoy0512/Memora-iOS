import SwiftUI

struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void

  /// The header names the conversation's scope, so the menu has a visible
  /// label even before a person is picked.
  private var scopeTitle: String {
    model.aiPersonScopeID.flatMap { model.person(id: $0)?.name } ?? "Memora"
  }

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      headerButton("メニュー", icon: .line3Horizontal, action: onOpenSidebar)
      Menu {
        if model.aiPersonScopeID != nil {
          Button("すべての記録の新しいチャット", icon: .squareAndPencil) { model.startNewAIChat() }
        }
        Button("検索", icon: .magnifyingglass, action: onSearch)
      } label: {
        Text(scopeTitle)
          .font(MemoraTypography.body.weight(.semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(MemoraQuietButtonStyle())
      .accessibilityLabel("\(scopeTitle)、検索")
      headerButton("履歴", icon: .clockArrowCirclepath, action: onHistory)
      headerButton("新しいチャット", icon: .squareAndPencil, action: onNewChat)
        .disabled(model.aiMessages.isEmpty)
    }
    .padding(.horizontal, MemoraSpacing.screen)
    .frame(minHeight: 48)
  }

  private func headerButton(_ title: String, icon: MemoraIcon, action: @escaping () -> Void) -> some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      ToolbarIconGlyph(icon: icon)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .memoraGlass(in: Circle(), interactive: true, backed: false)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}
