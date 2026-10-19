import SwiftUI

/// A teammate's shared project: whose it is, and the records it held when they
/// last published it. Opening a record shows it read-only.
struct SharedProjectView: View {
  @Environment(MemoraModel.self) private var model
  var projectID: String

  var body: some View {
    if let project = model.cloudSharing.sharedProject(id: projectID) {
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            SharedOwnerBadge(ownerName: project.ownerName)
            Label(project.name, icon: project.icon)
              .font(.title2.bold())
            Text("\(project.ownerName)さんのプロジェクトです。閲覧のみで、編集はできません。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, MemoraSpacing.sm)
          .listRowSeparator(.hidden)
        }

        Section {
          if project.records.isEmpty {
            Text("記録はありません")
              .foregroundStyle(.secondary)
          } else {
            ForEach(project.records) { record in
              NavigationLink(value: LibraryRoute.sharedRecord(record.id)) {
                MeetingRow(meeting: record.meeting, showsDisclosure: false, sharedBy: record.ownerName)
              }
            }
          }
        } header: {
          Text("記録 \(project.records.count)件")
        }
      }
      .listStyle(.plain)
      .navigationTitle(project.name)
      .navigationBarTitleDisplayMode(.inline)
    } else {
      ContentUnavailableView(
        "共有が見つかりません",
        icon: .person3,
        description: Text("共有が停止されたか、まだ読み込まれていません。")
      )
    }
  }
}
