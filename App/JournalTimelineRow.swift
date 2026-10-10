import SwiftUI

struct JournalTimelineRow<Content: View>: View {
  var time: String
  var icon: MemoraIcon
  var tint: Color = .primary
  var railColor: Color = .indigo
  var connectsToNext = true
  @ViewBuilder var content: () -> Content
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var timeWidth = 38.0

  var body: some View {
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
        .foregroundStyle(tint)
        .frame(width: 44, height: 44)
        .background(Color(uiColor: .systemBackground), in: Circle())
        .memoraGlass(in: Circle())
        .accessibilityHidden(true)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 8)
    }
    .background {
      if connectsToNext {
        GeometryReader { geometry in
          Rectangle()
            .fill(LinearGradient(colors: [railColor.opacity(0.65), .indigo.opacity(0.25)],
              startPoint: .top, endPoint: .bottom))
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
