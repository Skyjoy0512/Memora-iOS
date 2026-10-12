import SwiftUI

struct LibraryRecordRow: View {
  var meeting: Meeting
  var showsPreview: Bool
  var isSelecting = false
  var isSelected = false
  var sharedBy: String?

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if isSelecting {
        Image(icon: isSelected ? .checkmarkCircleFill : .circle)
          .font(.body)
          .frame(width: ProjectLayout.iconSide)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 4) {
        ProjectRecordRow(meeting: meeting)
        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
            .padding(.leading, ProjectLayout.iconSide + 12)
        }
        if SampleContent.isSample(meetingID: meeting.id) {
          SampleTag().padding(.leading, ProjectLayout.iconSide + 12)
        }
        if meeting.status == .ready {
          MeetingStatusLabel(status: meeting.status)
            .font(.footnote)
            .padding(.leading, ProjectLayout.iconSide + 12)
        }
        if showsPreview, hasPreview {
          Text(meeting.shortSummaryPreview)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.leading, ProjectLayout.iconSide + 12)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .foregroundStyle(.primary)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var hasPreview: Bool {
    switch meeting.status {
    case .ready, .partialFailure: !meeting.shortSummaryPreview.isEmpty
    default: false
    }
  }
}
