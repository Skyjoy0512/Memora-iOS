import SwiftUI

struct AIChatAttachmentSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  var researchSelected = false
  var onResearch: (() -> Void)?
  var onSelect: (AIComposerAttachmentAction) -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MemoraSpacing.md) {
          let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: MemoraSpacing.sm))
            : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
          let labelLayout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: MemoraSpacing.md))
            : AnyLayout(VStackLayout(spacing: MemoraSpacing.sm))
          layout {
            ForEach([AIComposerAttachmentAction.camera, .photo, .file]) { action in
              Button { select(action) } label: {
                labelLayout {
                  Image(icon: action.icon, size: 22).accessibilityHidden(true)
                  Text(action.displayTitle)
                }
                  .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget,
                    alignment: typeSize.isAccessibilitySize ? .leading : .center)
                  .padding(.vertical, MemoraSpacing.xs)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          Divider()
          Button { select(.photo) } label: {
            Label("最近の写真を表示", icon: .photoOnRectangle)
              .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if let onResearch {
            Toggle("Webで検索", isOn: Binding(get: { researchSelected }, set: { _ in onResearch() }))
              .frame(minHeight: MemoraSpacing.touchTarget)
          }
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.vertical, MemoraSpacing.lg)
        .frame(maxWidth: .infinity)
      }
      .background(MemoraPalette.background)
      .navigationTitle("チャットに追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(280), .large])
    .presentationDragIndicator(.visible)
  }

  private func select(_ action: AIComposerAttachmentAction) {
    onSelect(action)
    dismiss()
  }
}
