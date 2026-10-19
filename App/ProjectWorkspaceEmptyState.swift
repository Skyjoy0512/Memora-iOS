import SwiftUI

/// One quiet context glyph leaves the first useful action as the focal point.
struct ProjectWorkspaceEmptyState: View {
  var icon: MemoraIcon
  var title: LocalizedStringKey
  var message: LocalizedStringKey
  var actionTitle: LocalizedStringKey
  var actionIcon: MemoraIcon
  var action: () -> Void

  var body: some View {
    VStack(spacing: MemoraSpacing.lg) {
      Image(icon: icon)
        .font(.system(size: 28, weight: .regular))
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(height: MemoraSpacing.touchTarget)
        .accessibilityHidden(true)

      VStack(spacing: MemoraSpacing.sm) {
        Text(title)
          .font(MemoraTypography.sectionHeading)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(MemoraTypography.secondary)
          .foregroundStyle(MemoraPalette.textSecondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .frame(maxWidth: 360)
      }

      Button(action: action) {
        Label {
          Text(actionTitle)
        } icon: {
          Image(icon: actionIcon)
        }
      }
      .buttonStyle(MemoraButtonStyle())
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MemoraSpacing.screen)
  }
}
