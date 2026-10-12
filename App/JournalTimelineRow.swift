import SwiftUI

struct JournalTimelineRow<Content: View>: View {
  var time: String
  var date: Date
  var icon: MemoraIcon
  var connectsToNext = true
  var nextDate: Date?
  @ViewBuilder var content: () -> Content
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.colorScheme) private var colorScheme
  @ScaledMetric(relativeTo: .caption) private var timeWidth = 38.0

  var body: some View {
    let hour = JournalTimelinePalette.hour(at: date)
    let nextHour = nextDate.map { next in
      Calendar.current.isDate(date, inSameDayAs: next) ? JournalTimelinePalette.hour(at: next) : 24
    } ?? hour

    HStack(alignment: .top, spacing: 10) {
      if !typeSize.isAccessibilitySize {
        Text(time)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .frame(width: timeWidth, alignment: .leading)
          .padding(.top, 4)
          .accessibilityHidden(true)
      }

      Image(icon: icon)
        .font(.title3)
        .foregroundStyle(LinearGradient(
          gradient: JournalTimelinePalette.gradient(from: hour, to: hour + 0.5, scheme: colorScheme),
          startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 44, height: 44)
        .background(Color(uiColor: .systemBackground), in: Circle())
        .memoraGlass(in: Circle())
        .accessibilityHidden(true)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 8)
    }
    .background {
      if connectsToNext {
        GeometryReader { geometry in
          Rectangle()
            .fill(LinearGradient(
              gradient: JournalTimelinePalette.gradient(from: hour, to: nextHour, scheme: colorScheme),
              startPoint: .top, endPoint: .bottom))
            .opacity(0.65)
            .frame(width: 5, height: max(0, geometry.size.height - 22))
            .offset(x: (typeSize.isAccessibilitySize ? 0 : timeWidth + 10) + 19.5, y: 22)
        }
        .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}
