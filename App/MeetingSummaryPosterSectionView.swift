import SwiftUI

struct MeetingSummaryPosterSectionView: View {
  var section: MeetingSummaryPosterSection

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if section.headings.count > 1 {
        Text(section.headings.dropLast().joined(separator: " / "))
          .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.black.opacity(0.6))
      }
      if let heading = section.headings.last {
        Text(heading).font(.system(size: 21, weight: .bold))
      }
      ForEach(section.groups) { group in
        MeetingSummaryPosterGroupView(group: group)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
