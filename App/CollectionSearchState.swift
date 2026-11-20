import SwiftUI

/// Search guidance stays near the field, above the keyboard rather than centered.
struct CollectionSearchState: View {
  var title: String
  var message: String
  var clear: (() -> Void)? = nil
  var clearTitle: LocalizedStringKey = "検索語を消去"
  var isEmbedded = false
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if isEmbedded {
      guidance
    } else {
      ScrollView { guidance }
        .frame(maxWidth: .infinity)
    }
  }

  private var guidance: some View {
    VStack(spacing: MemoraSpacing.sm) {
      Text(title).font(.headline).accessibilityAddTraits(.isHeader)
      Text(message).font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
        .lineSpacing(MemoraSpacing.xs)
      // Embedded results already have a clear button next to the query.
      if let clear, !isEmbedded || !typeSize.isAccessibilitySize {
        Button(clearTitle, action: clear)
          .buttonStyle(MemoraButtonStyle(emphasis: .secondary))
          .padding(.top, MemoraSpacing.sm)
      }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: MemoraSpacing.messageWidth)
    .padding(.horizontal, MemoraSpacing.screen)
    .frame(maxWidth: .infinity)
    .padding(.vertical, isEmbedded ? MemoraSpacing.lg : MemoraSpacing.section)
  }
}
