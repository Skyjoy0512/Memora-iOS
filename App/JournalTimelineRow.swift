import SwiftUI

struct JournalTimelineRow<Content: View>: View {
  var time: String
  var date: Date
  var icon: MemoraIcon
  var connectsToNext = true
  var nextDate: Date?
  @ViewBuilder var content: () -> Content

  var body: some View {
    HStack(alignment: .top, spacing: JournalTimelineMetrics.columnSpacing) {

      Image(icon: icon, size: 20)
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(width: JournalTimelineMetrics.iconSide, height: JournalTimelineMetrics.iconSide)
        .accessibilityHidden(true)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MemoraSpacing.sm)
        .padding(.bottom, MemoraSpacing.lg)
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
    0
  }
}

private enum JournalTimelineMetrics {
  static let iconSide: CGFloat = 44
  static let lineWidth: CGFloat = 1.5
  static let columnSpacing: CGFloat = 10
}
