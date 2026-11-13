import SwiftUI

/// Draws one block of a markdown document. Shared by the read-only document
/// and the editable one, so editing a block never changes how the others look.
struct MarkdownBlockView: View {
  var block: MarkdownBlock
  @ScaledMetric(relativeTo: .body) private var readingLineSpacing = MemoraTypography.readingLineSpacing
  @ScaledMetric(relativeTo: .body) private var listIndent = MemoraTypography.listIndent

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
        .font(MemoraTypography.readingBody)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(readingLineSpacing)

    case .bullet(let level, let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm) {
        MarkdownBulletMarker(marker: marker, level: level)
          .frame(minWidth: listIndent, alignment: .trailing)
        Self.inline(text)
          .font(Self.bulletFont(level))
          .lineSpacing(readingLineSpacing)
      }
      .padding(.leading, CGFloat(min(level, 4)) * listIndent)

    case .quote(let text):
      HStack(alignment: .top, spacing: MemoraSpacing.md) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(MemoraPalette.border)
          .frame(width: 3)
        Self.inline(text)
          .font(MemoraTypography.readingBody)
          .foregroundStyle(MemoraPalette.textSecondary)
          .lineSpacing(readingLineSpacing)
      }
      .fixedSize(horizontal: false, vertical: true)

    case .table(let header, let rows):
      VStack(alignment: .leading, spacing: 0) {
        ForEach(rows.indices, id: \.self) { index in
          MarkdownTableRow(header: header, row: rows[index]) { _, value, font in
            Self.inline(value).font(font)
          }
        }
      }

    case .rule:
      Divider()
        .padding(.vertical, MemoraSpacing.sm)

    case .code(_, let text):
      Text(verbatim: text)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Room between lines, so a long summary does not read as one dense block.
  static let lineSpacing = MemoraTypography.readingLineSpacing
  /// Room between blocks.
  static let blockSpacing = MemoraTypography.paragraphSpacing

  static func headingFont(_ level: Int) -> Font {
    MemoraTypography.heading(level)
  }

  /// A heading sits closer to what follows it than to what came before, so
  /// each section reads as one group.
  static func headingTopPadding(_ level: Int) -> CGFloat {
    level <= 2 ? MemoraSpacing.lg : MemoraSpacing.sm
  }

  static func bulletFont(_ level: Int) -> Font {
    MemoraTypography.readingBody
  }

  static func inline(_ text: String) -> some View {
    MarkdownInlineText(markdown: text)
  }
}

/// The dot, number or checkbox in front of a list item.
struct MarkdownBulletMarker: View {
  var marker: MarkdownBlock.Marker
  var level: Int

  var body: some View {
    switch marker {
    case .dot:
      if level > 0 {
        Image(icon: .arrowTurnDownRight, size: 16)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      } else {
        Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
      }
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
