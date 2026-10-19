import SwiftUI

struct ProjectRecordRow: View {
  var meeting: Meeting

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(icon: meeting.source.icon)
        .font(.body)
        .frame(width: ProjectLayout.iconSide, height: 24)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(meeting.displayTitle)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(MemoraFormat.relativeDate(meeting.createdAt)) · \(meeting.source.label) · \(MemoraFormat.duration(meeting.duration))")
          .font(MemoraTypography.metadata)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if meeting.status != .ready { MeetingStatusLabel(status: meeting.status) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: ProjectLayout.minimumRowHeight, alignment: .center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
