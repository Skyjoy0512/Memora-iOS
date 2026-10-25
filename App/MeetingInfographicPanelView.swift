import SwiftUI

struct MeetingInfographicPanelView: View {
  var panel: MeetingInfographic.Panel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(panel.title).font(.system(size: 20, weight: .bold)).fixedSize(horizontal: false, vertical: true)
      ForEach(panel.items.enumerated(), id: \.element.id) { index, item in
        VStack(alignment: .leading, spacing: 8) {
          if index > 0, panel.kind == .flow || panel.kind == .timeline {
            Text("↓").font(.system(size: 24)).foregroundStyle(.secondary).accessibilityHidden(true)
          }
          Text(item.label).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
          Text(item.text)
            .font(.system(size: panel.kind == .metric && index == 0 ? 44 : 24, weight: .semibold))
            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if panel.kind == .comparison, index < panel.items.count - 1 { Divider() }
      }
    }
    .padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color(white: panel.kind == .metric ? 0.94 : 0.98))
    .overlay(Rectangle().stroke(Color(white: 0.86), lineWidth: 1))
  }
}
