import SwiftUI

/// Search guidance stays near the field, above the keyboard rather than centered.
struct CollectionSearchState: View {
  var title: String
  var message: String

  var body: some View {
    VStack(spacing: MemoraSpacing.sm) {
      Text(title).font(.headline)
      Text(message).font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
        .lineSpacing(MemoraSpacing.xs)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: MemoraSpacing.messageWidth)
    .padding(.horizontal, MemoraSpacing.screen)
    .frame(maxWidth: .infinity)
    .padding(.top, MemoraSpacing.section)
    .accessibilityElement(children: .combine)
  }
}
