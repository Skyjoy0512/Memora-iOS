import SwiftUI

struct MeetingSummaryPosterGroupView: View {
  var group: MeetingSummaryPosterSection.Group

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(group.lines) { line in
        HStack(alignment: .top, spacing: 9) {
          if line.depth > 0 {
            Text("↳").foregroundStyle(Color.black.opacity(0.4))
          } else if !line.prefix.isEmpty {
            Text(line.prefix).foregroundStyle(Color.black.opacity(0.6))
          }
          Text(line.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(3)
        }
        .font(.system(size: line.depth > 0 ? 18 : 21, weight: line.depth > 0 ? .regular : .medium))
        .padding(.leading, CGFloat(min(line.depth, 3)) * 16)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
