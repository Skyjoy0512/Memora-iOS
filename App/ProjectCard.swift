import SwiftUI

struct ProjectCard: View {
  var space: MemoraSpace
  var recordCount: Int
  var taskCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Image(icon: space.icon)
        .font(.title2)
        .frame(width: 44, height: 44)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
      Text(space.name)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { counts }
        VStack(alignment: .leading, spacing: 6) { counts }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
    .foregroundStyle(.primary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .memoraCard(fill: Color(uiColor: .secondarySystemGroupedBackground))
    .contentShape(RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var counts: some View {
    Label("記録 \(recordCount)件", icon: .waveform)
    Label("タスク \(taskCount)件", icon: .checklist)
  }
}
