import SwiftUI

/// The records an answer was built from. Each answer surface keeps its own
/// container, navigation and glyphs, but the row itself reads the same way.
enum AIAnswerSourceViews {
  /// Names the record before its stored lines, so a spoken source says what it
  /// is without the visual header being repeated.
  static func spokenLabel(for source: AIChatSource) -> String {
    var parts = ["AIに渡した参考資料: \(source.title)"]
    parts.append(contentsOf: source.excerpts.map { MemoraFormat.duration($0.start) + "、" + $0.text })
    return parts.joined(separator: "、")
  }

  struct Header: View {
    var source: AIChatSource
    var icon: MemoraIcon
    var iconSize: CGFloat
    var spacing: CGFloat
    var fontWeight: Font.Weight
    var lineLimit: Int?
    var spacerMinLength: CGFloat?
    var trailingIcon: MemoraIcon
    var trailingIconSize: CGFloat

    var body: some View {
      HStack(spacing: spacing) {
        Image(icon: icon, size: iconSize)
        Text(source.title)
          .font(.subheadline.weight(fontWeight))
          .lineLimit(lineLimit)
        Spacer(minLength: spacerMinLength)
        Image(icon: trailingIcon, size: trailingIconSize)
      }
      .foregroundStyle(.primary)
    }
  }

  struct ExcerptRow: View {
    var excerpt: AIChatSource.Excerpt

    var body: some View {
      HStack(alignment: .top, spacing: 8) {
        Text(MemoraFormat.duration(excerpt.start))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(excerpt.text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
