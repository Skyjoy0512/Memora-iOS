import SwiftUI

struct MarketplaceDescription: View {
  var text: String
  @State private var expanded = false
  @State private var fullHeight: CGFloat = 0
  @State private var collapsedHeight: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
      Text(text)
        .font(.body)
        .foregroundStyle(MemoraPalette.textSecondary)
        .lineSpacing(4)
        .lineLimit(expanded ? nil : 3)
        .textSelection(.enabled)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
          if !expanded { collapsedHeight = height }
        }
        .background {
          Text(text)
            .font(.body)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        }
      if expanded || fullHeight > collapsedHeight + 1 {
        Button(expanded ? "閉じる" : "もっと見る") {
          expanded.toggle()
        }
        .font(.subheadline)
        .foregroundStyle(MemoraPalette.focus)
        .frame(minHeight: 44, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
