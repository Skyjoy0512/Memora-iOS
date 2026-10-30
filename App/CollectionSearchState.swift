import SwiftUI

/// Search guidance stays near the field, above the keyboard rather than centered.
struct CollectionSearchState: View {
  var title: String
  var message: String
  var clear: (() -> Void)? = nil

  var body: some View {
    ScrollView {
      VStack(spacing: MemoraSpacing.sm) {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        Text(message).font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
          .lineSpacing(MemoraSpacing.xs)
        if let clear {
          Button("検索語を消去", action: clear)
            .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
            .padding(.top, MemoraSpacing.sm)
        }
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: MemoraSpacing.messageWidth)
      .padding(.horizontal, MemoraSpacing.screen)
      .frame(maxWidth: .infinity)
      .padding(.vertical, MemoraSpacing.section)
    }
    .frame(maxWidth: .infinity)
  }
}
