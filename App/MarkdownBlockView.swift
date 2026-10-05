import SwiftUI

/// Draws one block of a markdown document. Shared by the read-only document
/// and the editable one, so editing a block never changes how the others look.
struct MarkdownBlockView: View {
  var block: MarkdownBlock
  @ScaledMetric(relativeTo: .body) private var readingLineSpacing: CGFloat = 7

  var body: some View {
    switch block {
    case .heading(let level, let text):
      Self.inline(text)
        .font(Self.headingFont(level))
        .foregroundStyle(.primary)
        .padding(.top, Self.headingTopPadding(level))
        .accessibilityAddTraits(.isHeader)

    case .paragraph(let text):
      Self.inline(text)
        .font(.body)
        .lineSpacing(readingLineSpacing)

    case .bullet(let level, let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        MarkdownBulletMarker(marker: marker, level: level)
        Self.inline(text)
          .font(Self.bulletFont(level))
          .lineSpacing(readingLineSpacing)
      }
      .padding(.leading, CGFloat(level) * 18)

    case .quote(let text):
      HStack(alignment: .top, spacing: 10) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(.quaternary)
          .frame(width: 3)
        Self.inline(text)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineSpacing(readingLineSpacing)
      }
      .fixedSize(horizontal: false, vertical: true)

    case .table(let header, let rows):
      VStack(alignment: .leading, spacing: 10) {
        ForEach(rows.indices, id: \.self) { index in
          MarkdownTableCard(header: header, row: rows[index])
        }
      }

    case .rule:
      Divider()
        .padding(.vertical, 8)
    }
  }

  /// Room between lines, so a long summary does not read as one dense block.
  static let lineSpacing: CGFloat = 6
  /// Room between blocks.
  static let blockSpacing: CGFloat = 12

  static func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: .title2.bold()
    case 2: .title3.bold()
    default: .headline
    }
  }

  /// A heading sits closer to what follows it than to what came before, so
  /// each section reads as one group.
  static func headingTopPadding(_ level: Int) -> CGFloat {
    level <= 2 ? 16 : 8
  }

  static func bulletFont(_ level: Int) -> Font {
    level == 0 ? .body : .subheadline
  }

  static func inline(_ text: String) -> Text {
    Text(InlineMarkdownEditor.attributed(text))
  }
}

/// The dot, number or checkbox in front of a list item.
struct MarkdownBulletMarker: View {
  var marker: MarkdownBlock.Marker
  var level: Int

  var body: some View {
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
}

/// A table row as a card: the first column is its title, the others labelled
/// lines, and empty cells are left out. Five columns do not fit an iPhone.
struct MarkdownTableCard: View {
  var header: [String]
  var row: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      MarkdownBlockView.inline(row.first ?? "")
        .font(.subheadline.weight(.semibold))

      ForEach(Array(row.enumerated().dropFirst()), id: \.offset) { index, value in
        if !value.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(header.indices.contains(index) ? header[index] : "")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(minWidth: 40, alignment: .leading)
            MarkdownBlockView.inline(value)
              .font(.subheadline)
              .lineSpacing(MarkdownBlockView.lineSpacing)
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
