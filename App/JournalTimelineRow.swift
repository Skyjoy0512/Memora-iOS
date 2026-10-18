import SwiftUI

struct JournalTimelineRow<Content: View>: View {
  var time: String
  var date: Date
  var icon: MemoraIcon
  var connectsToNext = true
  var nextDate: Date?
  @ViewBuilder var content: () -> Content
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var timeWidth = 38.0

  var body: some View {
    HStack(alignment: .top, spacing: JournalTimelineMetrics.columnSpacing) {
      if !typeSize.isAccessibilitySize {
        Text(time)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .frame(width: timeWidth, height: JournalTimelineMetrics.iconSide, alignment: .leading)
          .accessibilityHidden(true)
      }

      Image(icon: icon)
        .font(.title3)
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(width: JournalTimelineMetrics.iconSide, height: JournalTimelineMetrics.iconSide)
        .background(MemoraPalette.card, in: Circle())
        .accessibilityHidden(true)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 8)
    }
    .background {
      if connectsToNext {
        GeometryReader { geometry in
          Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: JournalTimelineMetrics.lineWidth, height: max(0, geometry.size.height - JournalTimelineMetrics.iconSide / 2))
            .offset(x: iconColumnLeading + (JournalTimelineMetrics.iconSide - JournalTimelineMetrics.lineWidth) / 2, y: JournalTimelineMetrics.iconSide / 2)
        }
        .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  /// The icon column's leading edge, so the hairline runs through its centre.
  private var iconColumnLeading: CGFloat {
    typeSize.isAccessibilitySize ? 0 : timeWidth + JournalTimelineMetrics.columnSpacing
  }
}

private enum JournalTimelineMetrics {
  static let iconSide: CGFloat = 44
  static let lineWidth: CGFloat = 1.5
  static let columnSpacing: CGFloat = 10
}
