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
        VStack(spacing: 16) {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
            ForEach([AIComposerAttachmentAction.camera, .photo, .file]) { action in
              Button { select(action) } label: {
                VStack(spacing: 10) {
                  Image(icon: action.icon, size: 22).accessibilityHidden(true)
                  Text(action.displayTitle).font(.body)
                }
                .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 76 : 100)
                .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
              }
              .buttonStyle(.plain)
            }
          }
          Button { select(.photo) } label: {
            Label("最近の写真を表示", icon: .photoOnRectangle)
              .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
              .padding(.horizontal, 20)
              .background(MemoraPalette.elevated, in: Capsule())
          }
          .buttonStyle(.plain).foregroundStyle(MemoraPalette.focus)
          if let onResearch {
            Toggle("Webで検索", isOn: Binding(get: { researchSelected }, set: { _ in onResearch() }))
              .padding(.horizontal, 8)
          }
        }
        .padding(20).frame(maxWidth: .infinity)
      }
      .background(MemoraPalette.secondaryBackground)
      .navigationTitle("チャットに追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .presentationDetents([.height(340), .large])
    .presentationDragIndicator(.visible)
  }

  private func select(_ action: AIComposerAttachmentAction) {
    onSelect(action)
    dismiss()
  }
}
