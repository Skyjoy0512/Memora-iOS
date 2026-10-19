import SwiftUI

struct LibraryRecordRow: View {
  var meeting: Meeting
  var showsPreview: Bool
  var isSelecting = false
  var isSelected = false
  var sharedBy: String?

  var body: some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      if isSelecting {
        Image(icon: isSelected ? .checkmarkCircleFill : .circle)
          .font(.body)
          .frame(width: ProjectLayout.iconSide)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        ProjectRecordRow(meeting: meeting, showsReadyStatus: true)
        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
            .padding(.leading, ProjectLayout.iconSide + MemoraSpacing.md)
        }
        if SampleContent.isSample(meetingID: meeting.id) {
          SampleTag().padding(.leading, ProjectLayout.iconSide + MemoraSpacing.md)
        }
        if showsPreview, hasPreview {
          Text(meeting.shortSummaryPreview)
            .font(MemoraTypography.secondary)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(2)
            .padding(.leading, ProjectLayout.iconSide + MemoraSpacing.md)
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
