import SwiftUI

/// Empty, filtered and search states share one reading rhythm, never a content card.
struct MemoraEmptyState: View {
  var icon: MemoraIcon
  var title: LocalizedStringKey
  var message: LocalizedStringKey
  var actionTitle: LocalizedStringKey? = nil
  var actionIcon: MemoraIcon = .plus
  var action: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: MemoraSpacing.lg) {
      Image(icon: icon, size: 28)
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(height: MemoraSpacing.touchTarget)
        .accessibilityHidden(true)
      VStack(spacing: MemoraSpacing.sm) {
        Text(title)
          .font(MemoraTypography.sectionHeading)
          .foregroundStyle(MemoraPalette.textPrimary)
          .accessibilityAddTraits(.isHeader)
        Text(message)
          .font(MemoraTypography.secondary)
          .foregroundStyle(MemoraPalette.textSecondary)
          .lineSpacing(MemoraSpacing.xs)
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      if let actionTitle, let action {
        Button(action: action) {
          Label { Text(actionTitle) } icon: { Image(icon: actionIcon) }
        }
        .buttonStyle(MemoraButtonStyle())
      }
    }
    .frame(maxWidth: MemoraSpacing.messageWidth)
    .padding(.horizontal, MemoraSpacing.screen)
    .frame(maxWidth: .infinity)
    .padding(.vertical, MemoraSpacing.lg)
  }
}
