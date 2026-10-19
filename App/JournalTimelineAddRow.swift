import SwiftUI

/// A quiet insertion point on the journal timeline. The circle sits on the
/// same hairline as the row icons, and the whole 44pt frame is tappable.
struct JournalTimelineAddRow: View {
  var label: String
  var isLast: Bool
  var action: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var timeWidth = 38.0

  private static let side: CGFloat = 44
  private static let lineWidth: CGFloat = 1.5
  private static let columnSpacing: CGFloat = 10

  var body: some View {
    HStack(spacing: Self.columnSpacing) {
      if !typeSize.isAccessibilitySize {
        Color.clear
          .frame(width: timeWidth, height: Self.side)
      }

      Button(action: action) {
        HStack(spacing: 6) {
          Image(icon: .plus)
            .font(.caption.weight(.bold))
          Text(displayLabel)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(MemoraPalette.textSecondary)
        .padding(.horizontal, MemoraSpacing.md)
        .frame(height: Self.side)
        .background(MemoraPalette.card, in: Capsule())
        .overlay {
          Capsule()
            .stroke(MemoraPalette.border.opacity(0.8), lineWidth: 0.5)
        }
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(label))

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      GeometryReader { geometry in
        Rectangle()
          .fill(Color.primary.opacity(0.12))
          .frame(width: Self.lineWidth, height: isLast ? Self.side / 2 : geometry.size.height)
          .offset(x: iconColumnLeading + (Self.side - Self.lineWidth) / 2, y: 0)
      }
      .accessibilityHidden(true)
    }
  }

  private var iconColumnLeading: CGFloat {
    typeSize.isAccessibilitySize ? 0 : timeWidth + Self.columnSpacing
  }

  /// The full sentence helps at ordinary sizes; at accessibility sizes the
  /// shorter form keeps the whole pill inside the row.
  private var displayLabel: String {
    guard typeSize.isAccessibilitySize else { return label }
    return isLast ? "記録を追加" : "この間に追加"
  }
}
