import SwiftUI

struct ProjectListRow: View {
  var space: MemoraSpace
  var recordCount: Int
  var latestRecordDate: Date?
  var rename: () -> Void
  var share: () -> Void
  var delete: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      NavigationLink(value: LibraryRoute.space(space.id)) {
        HStack(spacing: 12) {
          Image(icon: space.icon)
            .font(.body)
            .frame(width: ProjectLayout.iconSide)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(space.name)
              .font(.body.weight(.semibold))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            Text(metadata)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(space.name)、\(metadata)")
      .accessibilityHint("プロジェクトを開きます")
      .contextMenu { actions }

      Menu { actions } label: {
        Image(icon: .ellipsis)
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("\(space.name)の操作")
    }
    .overlay(alignment: .bottom) {
      Divider().padding(.leading, ProjectLayout.iconSide + 12).accessibilityHidden(true)
    }
  }

  private var metadata: String {
    let count = "記録 \(recordCount)件"
    guard let latestRecordDate else { return count }
    return "\(count) · 最新記録 \(latestRecordDate.formatted(date: .abbreviated, time: .omitted))"
  }

  @ViewBuilder private var actions: some View {
    Button("名前を変更", icon: .pencil, action: rename)
    Button("チームで共有", icon: .personBadgePlus, action: share)
    Divider()
    Button("削除", icon: .trash, role: .destructive, action: delete)
  }
}
