import SwiftUI

struct ProjectRecordRow: View {
  var meeting: Meeting
  var showsReadyStatus = false
  var showsSourceIcon = true
  var reservesSelectionSpace = false
  var selectionState: Bool? = nil
  var minimumHeight: CGFloat = ProjectLayout.minimumRowHeight

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .top, spacing: MemoraSpacing.md))
    let metadata = [MemoraFormat.relativeDate(meeting.createdAt), meeting.source.label]
      + (meeting.duration > 0 ? [MemoraFormat.duration(meeting.duration)] : [])
    return layout {
      if showsSourceIcon {
        Image(icon: meeting.source.icon, size: 17)
          .frame(width: ProjectLayout.iconSide, height: 24)
          .foregroundStyle(MemoraPalette.textSecondary)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(meeting.displayTitle)
          .font(MemoraTypography.body.weight(.medium))
          .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .top, spacing: MemoraSpacing.sm) {
          Text(metadata.joined(separator: " · "))
            .font(MemoraTypography.metadata)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          // A swipe can still be settling when selection starts. Keep the
          // metadata's wrapping and the cell's measured height stable.
          if reservesSelectionSpace || selectionState != nil {
            Image(icon: selectionState == true ? .checkmarkCircleFill : .circle, size: 17)
              .frame(width: ProjectLayout.iconSide, height: 20)
              .opacity(selectionState == nil ? 0 : 1)
              .accessibilityHidden(true)
          }
        }
        .foregroundStyle(MemoraPalette.textSecondary)
        if showsReadyStatus || meeting.status != .ready {
          MeetingStatusLabel(status: meeting.status)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: minimumHeight, alignment: .center)
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
