import SwiftUI

struct AskAIHeader: View {
  @Environment(MemoraModel.self) private var model
  var onOpenSidebar: () -> Void
  var onNewChat: () -> Void
  var onHistory: () -> Void
  var onSearch: () -> Void

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      headerButton("メニュー", icon: .line3Horizontal, action: onOpenSidebar)
      Menu {
        if model.aiPersonScopeID != nil {
          Button("すべての記録の新しいチャット", icon: .squareAndPencil) { model.startNewAIChat() }
        }
        Button("履歴", icon: .clockArrowCirclepath, action: onHistory)
        Button("検索", icon: .magnifyingglass, action: onSearch)
      } label: {
        HStack(spacing: MemoraSpacing.xs) {
          Text(model.aiPersonScopeID.flatMap { model.person(id: $0)?.name } ?? "Memora")
            .font(MemoraTypography.body.weight(.semibold))
            .lineLimit(1)
          Image(icon: .chevronDown, size: MemoraIconMetrics.accessory)
            .foregroundStyle(MemoraPalette.textSecondary)
            .accessibilityHidden(true)
        }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(MemoraQuietButtonStyle())
      .accessibilityLabel("Memora、履歴と検索")
      Spacer(minLength: MemoraSpacing.sm)
      headerButton("新しいチャット", icon: .squareAndPencil, action: onNewChat)
        .disabled(model.aiMessages.isEmpty)
    }
    .padding(.horizontal, MemoraSpacing.md)
    .frame(minHeight: 48)
  }

  private func headerButton(_ title: String, icon: MemoraIcon, action: @escaping () -> Void) -> some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      ToolbarIconGlyph(icon: icon)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityLabel(title)
  }
}
