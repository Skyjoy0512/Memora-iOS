import SwiftUI

/// Stacked table values keep all columns readable without compressing Japanese text.
/// Reading and inline editing use the same geometry and type roles.
struct MarkdownTableRow<Cell: View>: View {
  var header: [String]
  var row: [String]
  @ViewBuilder var cell: (Int, String, Font) -> Cell
  @ScaledMetric(relativeTo: .body) private var lineSpacing = MemoraTypography.readingLineSpacing

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Divider()
      ForEach(row.indices, id: \.self) { column in
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          if header.indices.contains(column), !header[column].isEmpty {
            Text(header[column])
              .font(MemoraTypography.metadata)
              .foregroundStyle(MemoraPalette.textSecondary)
          }
          cell(column, row[column], column == 0 ? MemoraTypography.body.weight(.semibold) : MemoraTypography.readingBody)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.vertical, MemoraSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
