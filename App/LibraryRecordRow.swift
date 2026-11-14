import SwiftUI

struct LibraryRecordRow: View {
  var meeting: Meeting
  var showsPreview: Bool
  var isSelecting = false
  var isSelected = false
  var sharedBy: String?

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .top, spacing: MemoraSpacing.md))
    return layout {
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        ProjectRecordRow(meeting: meeting, showsReadyStatus: false, showsSourceIcon: false,
          selectionState: isSelecting ? isSelected : nil)
        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
            .padding(.leading, typeSize.isAccessibilitySize ? 0 : ProjectLayout.iconSide + MemoraSpacing.md)
        }
        if SampleContent.isSample(meetingID: meeting.id) {
          SampleTag().padding(.leading, typeSize.isAccessibilitySize ? 0 : ProjectLayout.iconSide + MemoraSpacing.md)
        }
        if showsPreview, hasPreview {
          Text(meeting.shortSummaryPreview)
            .font(MemoraTypography.secondary)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .padding(.leading, typeSize.isAccessibilitySize ? 0 : ProjectLayout.iconSide + MemoraSpacing.md)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .foregroundStyle(.primary)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .accessibilityValue(isSelecting ? (isSelected ? "選択済み" : "未選択") : "")
    .accessibilityHint(isSelecting ? "タップして選択を切り替えます" : "記録を開きます")
  }

  private var hasPreview: Bool {
    switch meeting.status {
    case .ready, .partialFailure: !meeting.shortSummaryPreview.isEmpty
    default: false
    }
  }
}
