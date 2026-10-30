import SwiftUI

struct ProjectRecordRow: View {
  var meeting: Meeting
  var showsReadyStatus = false

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .top, spacing: MemoraSpacing.md))
    return layout {
      Image(icon: meeting.source.icon, size: 17)
        .frame(width: ProjectLayout.iconSide, height: 24)
        .foregroundStyle(MemoraPalette.textSecondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(meeting.displayTitle)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(MemoraFormat.relativeDate(meeting.createdAt)) · \(meeting.source.label) · \(MemoraFormat.duration(meeting.duration))")
          .font(MemoraTypography.metadata)
          .foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        if showsReadyStatus || meeting.status != .ready {
          MeetingStatusLabel(status: meeting.status)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: ProjectLayout.minimumRowHeight, alignment: .center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
