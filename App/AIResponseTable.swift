import SwiftUI

// Table row layout adapted from ChatGPTMarkdownView, MIT, dc6e6a52.
// Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt.
struct AIResponseTable: View {
  var header: [String]
  var rows: [[String]]
  @State private var availableWidth: CGFloat = 0
  @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 88

  var body: some View {
    let widths = AIResponseTableLayout.widths(header: header, rows: rows,
      availableWidth: availableWidth, minimumWidth: minimumColumnWidth)
    ScrollView(.horizontal) {
      VStack(alignment: .leading, spacing: 0) {
        row(header, widths: widths, isHeader: true)
        Divider()
        // Markdown tables have positional cells; streaming only appends rows.
        ForEach(rows.indices, id: \.self) { index in
          row(rows[index], widths: widths, isHeader: false)
          Divider()
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

  private func row(_ cells: [String], widths: [CGFloat], isHeader: Bool) -> some View {
    HStack(alignment: .top, spacing: 24) {
      ForEach(header.indices, id: \.self) { column in
        MarkdownBlockView.inline(cells.indices.contains(column) ? cells[column] : "")
          .font(isHeader ? .body.weight(.semibold) : .body)
          .lineSpacing(5)
          .frame(width: widths[column], alignment: .leading)
          .padding(.vertical, MemoraSpacing.md)
          .accessibilityAddTraits(isHeader ? .isHeader : [])
      }
    }
  }
}
