import SwiftUI

/// Draws a structured markdown document — headings, nested lists, quotes,
/// rules and tables — for generated summaries. A table's rows become compact
/// cards, since five columns do not fit an iPhone's width.
struct MarkdownDocumentView: View {
  var markdown: String

  var body: some View {
    let blocks = MarkdownBlockParser.blocks(for: markdown)

    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        view(for: block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func view(for block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      heading(text, level: level)

    case .paragraph(let text):
      inline(text)
        .font(.body)

    case .bullet(let level, let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        bulletMarker(marker, level: level)
        inline(text)
          .font(level == 0 ? .body : .subheadline)
      }
      .padding(.leading, CGFloat(level) * 18)

    case .quote(let text):
      HStack(alignment: .top, spacing: 10) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(.quaternary)
          .frame(width: 3)
        inline(text)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)

    case .table(let header, let rows):
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          tableCard(header: header, row: row)
        }
      }

    case .rule:
      Divider()
        .padding(.vertical, 6)
    }
  }

  private func heading(_ text: String, level: Int) -> some View {
    let font: Font = switch level {
    case 1: .title2.bold()
    case 2: .title3.bold()
    default: .headline
    }
    return inline(text)
      .font(font)
      .foregroundStyle(.primary)
      .padding(.top, level <= 2 ? 10 : 4)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private func bulletMarker(_ marker: MarkdownBlock.Marker, level: Int) -> some View {
    switch marker {
    case .dot:
      Text(level == 0 ? "•" : "◦")
        .foregroundStyle(.secondary)
    case .number(let number):
      Text("\(number).")
        .monospacedDigit()
        .foregroundStyle(.secondary)
    case .checkbox(let isChecked):
      Image(icon: isChecked ? .checkmarkSquare : .square)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isChecked ? "完了" : "未完了")
    }
  }

  /// The first column is the row's title; the others are labelled lines, and
  /// empty cells are left out.
  private func tableCard(header: [String], row: [String]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      inline(row.first ?? "")
        .font(.subheadline.weight(.semibold))

      ForEach(Array(row.enumerated().dropFirst()), id: \.offset) { index, value in
        if !value.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(header.indices.contains(index) ? header[index] : "")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(minWidth: 40, alignment: .leading)
            inline(value)
              .font(.subheadline)
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func inline(_ text: String) -> Text {
    Text(InlineMarkdownEditor.attributed(text))
  }
}
