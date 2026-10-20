import SwiftUI

/// A read-only comparison table for the structured interface.
///
/// A header row states the columns in secondary weight, every data row shares
/// the header's column widths, and hairline dividers separate the rows. A long
/// cell wraps inside its column instead of squeezing its neighbours, and the
/// whole table scrolls horizontally when it cannot fit. The layout follows
/// OpenUI's `ScrollableTable` idea (MIT, 8d9c4c3b) as an independent SwiftUI
/// implementation; no React code is copied.
struct AIInterfaceComparisonTable: View {
  var columns: [String]
  var items: [NativeAIInterface.Item]
  var messageID: UUID?
  /// A row's optional evidence ID mapped to a target that is permitted now.
  var evidenceTargets: [UUID: AIInterfaceReferenceTarget]

  @State private var availableWidth: CGFloat = 0
  @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 96

  var body: some View {
    let widths = AIInterfaceTableLayout.widths(header: columns, rows: items.map { $0.cells ?? [] },
      availableWidth: availableWidth, minimumWidth: minimumColumnWidth, spacing: 16)
    ScrollView(.horizontal) {
      VStack(alignment: .leading, spacing: 0) {
        row(cells: columns, widths: widths, item: nil, isHeader: true)
        hairline
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          row(cells: item.cells ?? [], widths: widths, item: item, isHeader: false)
          if index < items.count - 1 { hairline }
        }
      }
      .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      if width > 0 { availableWidth = width }
    }
    .accessibilityLabel("比較表。横にスクロールできます")
  }

  private func row(cells: [String], widths: [CGFloat], item: NativeAIInterface.Item?, isHeader: Bool) -> some View {
    HStack(alignment: .top, spacing: 16) {
      ForEach(columns.indices, id: \.self) { column in
        Text(cells.indices.contains(column) ? cells[column] : "")
          .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
          .foregroundStyle(isHeader ? MemoraPalette.textSecondary : MemoraPalette.textPrimary)
          .lineSpacing(isHeader ? 0 : 3)
          .frame(width: widths.indices.contains(column) ? widths[column] : minimumColumnWidth, alignment: .leading)
          .padding(.vertical, isHeader ? 10 : 12)
          .accessibilityAddTraits(isHeader ? .isHeader : [])
      }
      if !isHeader, let id = item?.referenceID, let target = evidenceTargets[id], let messageID {
        NavigationLink {
          AIInterfaceReferenceDestination(messageID: messageID, target: target)
        } label: {
          Image(icon: .link, size: 13)
            .font(.footnote)
            .foregroundStyle(MemoraPalette.textSecondary)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("根拠を開く")
      }
    }
  }

  private var hairline: some View {
    Rectangle().fill(MemoraPalette.border).frame(height: 1)
  }
}
