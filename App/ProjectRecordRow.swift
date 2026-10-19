import SwiftUI

struct ProjectRecordRow: View {
  var meeting: Meeting
  var showsReadyStatus = false

  var body: some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      Image(icon: meeting.source.icon)
        .font(.body)
        .frame(width: ProjectLayout.iconSide, height: 24)
        .foregroundStyle(MemoraPalette.textSecondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(meeting.displayTitle)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(2)
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
