import SwiftUI

/// Source disclosure can wrap below actions without squeezing either control.
struct AIReplyActionsRow: View {
  var message: AIChatMessage
  var excerptCount: Int
  var isSourcesOpen: Bool
  var toggleSources: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.sm))
    layout {
      AIAnswerActions(message: message)
      if excerptCount > 0 {
        Button(action: toggleSources) {
          HStack(spacing: MemoraSpacing.xs) {
            MemoraInterfaceIcon(icon: .docText)
            Text("発言 \(excerptCount)件").font(MemoraTypography.metadata)
              .fixedSize(horizontal: false, vertical: true)
            Image(icon: .chevronDown)
              .font(.system(size: MemoraIconMetrics.accessory, weight: .medium))
              .rotationEffect(.degrees(isSourcesOpen ? 180 : 0))
          }
          .foregroundStyle(MemoraPalette.textSecondary)
          .padding(.horizontal, MemoraSpacing.sm)
          .frame(minHeight: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("根拠になった発言")
        .accessibilityValue(isSourcesOpen ? "開いています" : "閉じています")
      }
    }
  }
}
