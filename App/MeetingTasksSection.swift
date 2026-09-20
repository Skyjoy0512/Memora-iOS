import SwiftUI

struct MeetingTasksSection: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID

  var body: some View {
    let meetingTasks = model.tasks(forMeeting: meetingID)
    VStack(alignment: .leading, spacing: 12) {
      Label("次にすること", systemImage: "arrow.right.circle")
        .font(.title3.bold())
        .foregroundStyle(.primary)

      if meetingTasks.isEmpty {
        Text("この会議からタスクは見つかりませんでした")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(meetingTasks) { task in
          TaskRow(task: task, showsMetadata: false)
        }
      }
    }
  }
}
