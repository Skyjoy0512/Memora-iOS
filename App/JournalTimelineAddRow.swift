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
        Image(icon: .plus)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(MemoraPalette.textSecondary)
          .frame(width: Self.side, height: Self.side)
          .background(Color(uiColor: .tertiarySystemFill), in: Circle())
          .contentShape(Circle())
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
}
