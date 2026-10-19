import SwiftUI

/// Inline action menu shares the candidate surface and keeps native input mounted.
struct ComposerActionMenu<Content: View>: View {
  var close: () -> Void
  var maximumHeight: CGFloat = 360
  @ViewBuilder var content: () -> Content
  @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
      HStack {
        Text("追加").font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
        Spacer()
        Button("追加メニューを閉じる", icon: .xmark, action: close)
          .labelStyle(.iconOnly).buttonStyle(.plain)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
      }
      .padding(.leading, MemoraSpacing.lg)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          content().buttonStyle(ComposerActionStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: max(44, min(maximumHeight - 56, rowHeight * 5 + MemoraSpacing.lg)))
      .scrollDismissesKeyboard(.never)
    }
    .padding(.bottom, MemoraSpacing.sm)
    .frame(width: 288)
    .background(MemoraPalette.elevated, in: RoundedRectangle(cornerRadius: MemoraRadius.card))
    .overlay { RoundedRectangle(cornerRadius: MemoraRadius.card).strokeBorder(MemoraPalette.border, lineWidth: 1) }
    .preservesComposerFocus()
  }
}

private struct ComposerActionStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(MemoraTypography.body)
      .foregroundStyle(MemoraPalette.textPrimary)
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.vertical, MemoraSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .background(configuration.isPressed ? MemoraPalette.selection : .clear)
      .contentShape(Rectangle())
  }
}
