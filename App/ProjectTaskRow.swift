import SwiftUI

struct ProjectTaskRow: View {
  @Environment(MemoraModel.self) private var model
  var task: MemoraTask
  var onOpen: () -> Void

  var body: some View {
    let sourceTitle = task.meetingID.flatMap { model.meetingTitles[$0] }
    let metadata = [task.assignee, sourceTitle].compactMap { $0 }.filter { !$0.isEmpty }
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        TaskRow(task: task, onOpen: onOpen)
          .fixedSize(horizontal: false, vertical: true)
        if !metadata.isEmpty {
          Text(metadata.joined(separator: " · "))
            .font(.footnote).foregroundStyle(.secondary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 56)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let meetingID = task.meetingID {
        NavigationLink(value: LibraryRoute.meeting(meetingID)) {
          Image(icon: .docText)
            .font(.body).foregroundStyle(.secondary)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 44)
        .accessibilityLabel("元の記録を開く、\(sourceTitle ?? "無題の記録")")
      }
    }
    .buttonStyle(.plain)
  }
}
