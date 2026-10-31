import SwiftUI

struct MarketplaceDetailFacts: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var fields: [(String, String)]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { index in
        if index > 0 { Divider() }
        if typeSize.isAccessibilitySize {
          fact(fields[index])
          if index + 1 < fields.count {
            Divider()
            fact(fields[index + 1])
          }
        } else {
          HStack(alignment: .top, spacing: 0) {
            fact(fields[index])
              .overlay(alignment: .trailing) {
                if index + 1 < fields.count {
                  Rectangle().fill(MemoraPalette.border).frame(width: 1).padding(.vertical, 16)
                }
              }
            if index + 1 < fields.count { fact(fields[index + 1]) }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("marketplace.detail.facts")
  }

  private func fact(_ field: (String, String)) -> some View {
    VStack(spacing: MemoraSpacing.sm) {
      Text(field.0).font(.subheadline).foregroundStyle(.secondary)
      Text(field.1).font(.headline).foregroundStyle(MemoraPalette.textPrimary)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MemoraSpacing.sm)
    .padding(.vertical, MemoraSpacing.xl)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(field.0)、\(field.1)")
  }
}
