import SwiftUI

struct MeetingRow: View {
  var meeting: Meeting
  var showsDisclosure = true
  var sharedBy: String?

  var body: some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      LibraryRecordRow(meeting: meeting, showsPreview: true, sharedBy: sharedBy)
      if showsDisclosure {
        Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
          .foregroundStyle(MemoraPalette.textSecondary)
          .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
