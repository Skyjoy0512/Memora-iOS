import SwiftUI

extension View {
  func memoraReadingText() -> some View {
    modifier(MemoraReadingText())
  }
}

/// Prose uses the same rhythm as rendered summaries and assistant replies.
private struct MemoraReadingText: ViewModifier {
  @ScaledMetric(relativeTo: .body) private var leading = MemoraTypography.readingLineSpacing

  func body(content: Content) -> some View {
    content
      .font(MemoraTypography.readingBody)
      .lineSpacing(leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
