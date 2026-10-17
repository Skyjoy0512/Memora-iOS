#if DEBUG
import SwiftUI

/// Frozen 7d9edb9 geometry for visual comparison; never used by real answers.
struct AIMarkdownBaselineExampleView: View {
  var text: String

  var body: some View {
    let blocks = MarkdownBlockParser.blocks(for: text)
    VStack(alignment: .leading, spacing: 12) {
      ForEach(blocks.indices, id: \.self) { index in
        switch blocks[index] {
        case .code(let language, let code):
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(language).font(.caption.monospaced()).foregroundStyle(.secondary)
              Spacer(minLength: 12)
              Image(icon: .docOnDoc).frame(width: 44, height: 44).accessibilityHidden(true)
            }.padding(.leading, 14).padding(.trailing, 4)
            Divider()
            ScrollView(.horizontal) {
              Text(verbatim: code).font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(14)
            }
          }.background(MemoraPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        case .table(let header, let rows):
          ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
              GridRow {
                ForEach(header.indices, id: \.self) { column in
                  MarkdownBlockView.inline(header[column]).font(.subheadline.weight(.semibold))
                    .frame(minWidth: 100, maxWidth: 220, alignment: .leading)
                }
              }
              Divider().gridCellUnsizedAxes(.horizontal)
              ForEach(rows.indices, id: \.self) { row in
                GridRow {
                  ForEach(header.indices, id: \.self) { column in
                    MarkdownBlockView.inline(rows[row].indices.contains(column) ? rows[row][column] : "")
                      .font(.subheadline).frame(minWidth: 100, maxWidth: 220, alignment: .leading)
                  }
                }
              }
            }.padding(.vertical, 8).textSelection(.enabled)
          }
        default: MarkdownBlockView(block: blocks[index])
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
#endif
