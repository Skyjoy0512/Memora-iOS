import SwiftUI

struct AIResponseTable: View {
  var header: [String]
  var rows: [[String]]

  var body: some View {
    ScrollView(.horizontal) {
      Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
        GridRow {
          ForEach(header.indices, id: \.self) { index in
            MarkdownBlockView.inline(header[index])
              .font(.subheadline.weight(.semibold))
              .frame(minWidth: 100, maxWidth: 220, alignment: .leading)
              .accessibilityAddTraits(.isHeader)
          }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
        ForEach(rows.indices, id: \.self) { rowIndex in
          GridRow {
            ForEach(header.indices, id: \.self) { column in
              MarkdownBlockView.inline(rows[rowIndex].indices.contains(column) ? rows[rowIndex][column] : "")
                .font(.subheadline)
                .frame(minWidth: 100, maxWidth: 220, alignment: .leading)
            }
          }.accessibilityElement(children: .combine)
        }
      }
      .padding(.vertical, 8).textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel("比較表。横にスクロールできます")
  }
}
