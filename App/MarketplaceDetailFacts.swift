import SwiftUI

struct MarketplaceDetailFacts: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var fields: [(String, String)]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("情報")
        .font(.headline)
        .padding(.bottom, MemoraSpacing.xl)
        .accessibilityAddTraits(.isHeader)
      ForEach(fields, id: \.0) { field in
        let layout = typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.sm))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MemoraSpacing.xl))
        layout {
          Text(field.0)
            .foregroundStyle(MemoraPalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(field.1)
            .foregroundStyle(MemoraPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, MemoraSpacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(field.0)、\(field.1)")
        if field.0 != fields.last?.0 { Divider() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("marketplace.detail.facts")
  }
}
