import SwiftUI

struct ProjectCard: View {
  var space: MemoraSpace
  var recordCount: Int
  var taskCount: Int
  var latestRecordDate: Date?
  var rename: () -> Void
  var share: () -> Void
  var delete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      NavigationLink(value: LibraryRoute.space(space.id)) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top, spacing: 12) {
            Image(icon: space.icon)
              .font(.title3.weight(.medium))
              .frame(width: 44, height: 44)
              .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
              Text(space.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
              if let latestRecordDate {
                Text("最新の記録 \(latestRecordDate.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                Text("最初の記録を追加しましょう")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { counts }
            VStack(alignment: .leading, spacing: 8) { counts }
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
        .padding(.vertical, 18)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityHint("プロジェクトの記録とタスクを開きます")
      .contextMenu { actions }

      // A sibling menu keeps its taps separate from the navigation link.
      Menu { actions } label: {
        Image(icon: .ellipsis)
          .font(.body.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("\(space.name)の操作")
      .padding(.top, 8)
      .padding(.trailing, 6)
    }
    .memoraCard(fill: Color(uiColor: .secondarySystemGroupedBackground))
  }

  @ViewBuilder private var counts: some View {
    Label("記録 \(recordCount)件", icon: .waveform)
    Label("未完了 \(taskCount)件", icon: .checklist)
  }

  @ViewBuilder private var actions: some View {
    Button("名前を変更", icon: .pencil, action: rename)
    Button("チームで共有", icon: .personBadgePlus, action: share)
    Divider()
    Button("削除", icon: .trash, role: .destructive, action: delete)
  }
}
