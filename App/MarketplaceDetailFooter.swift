import SwiftUI

struct MarketplaceDetailFooter<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .buttonStyle(.plain)
      .frame(maxWidth: MemoraSpacing.readingWidth)
      .padding(.horizontal, MemoraSpacing.section)
      .padding(.top, MemoraSpacing.md)
      .padding(.bottom, MemoraSpacing.sm)
      .frame(maxWidth: .infinity)
      .background(MemoraPalette.background)
  }
}
