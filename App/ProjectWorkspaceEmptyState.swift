import SwiftUI

/// The first thing a workspace tab shows when it holds nothing yet: a small
/// stack of related symbols, one sentence of orientation, and the action that
/// fills the tab. It stays monochrome so it belongs to the rest of Memora.
struct ProjectWorkspaceEmptyState: View {
  var icons: [MemoraIcon]
  var title: LocalizedStringKey
  var message: LocalizedStringKey
  var actionTitle: LocalizedStringKey
  var actionIcon: MemoraIcon
  var action: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      HStack(spacing: -9) {
        ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
          Image(icon: icon)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(MemoraPalette.textSecondary)
            .frame(width: 44, height: 44)
            .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MemoraPalette.border, lineWidth: 1.5)
            }
        }
      }
      .accessibilityHidden(true)

      VStack(spacing: 7) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .frame(maxWidth: 320)
      }

      Button(action: action) {
        Label {
          Text(actionTitle)
        } icon: {
          Image(icon: actionIcon)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MemoraPalette.actionLabel)
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
        .background(MemoraPalette.action, in: Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
  }
}
