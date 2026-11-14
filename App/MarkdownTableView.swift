import SwiftUI

/// A table keeps its columns together while horizontal scrolling makes room
/// for comparison. Reading and inline editing share this exact geometry.
struct MarkdownTableView<Cell: View>: View {
  var header: [String]
  var rows: [[String]]
  @ViewBuilder var cell: (Int, Int, String) -> Cell
  @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 168

  var body: some View {
    ScrollView(.horizontal) {
      VStack(alignment: .leading, spacing: 0) {
        tableRow(header, at: -1)
          .font(MemoraTypography.secondary.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        Divider()
        // Coordinates are the table editor's cell addresses. Cells hold no
        // independent state and changing structure never reorders saved rows.
        ForEach(rows.indices, id: \.self) { row in
          tableRow(rows[row], at: row)
            .font(MemoraTypography.readingBody)
          if row < rows.count - 1 { Divider() }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHint("表は横にスクロールして各列を確認できます")
  }

  private func tableRow(_ values: [String], at row: Int) -> some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      ForEach(header.indices, id: \.self) { column in
        cell(row, column, values.indices.contains(column) ? values[column] : "")
          .frame(width: min(columnWidth, 280), alignment: .leading)
          .frame(minHeight: MemoraSpacing.touchTarget, alignment: .topLeading)
      }
    }
    .padding(.vertical, MemoraSpacing.sm)
  }
}
