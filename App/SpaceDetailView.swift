import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var spaceID: UUID
  @State private var isAskingAI = false
  @State private var isRenaming = false
  @State private var isDeleting = false

  var body: some View {
    if let space = model.space(id: spaceID) {
      // Filtered once per redraw; each row used to filter again for its divider.
      let spaceMeetings = model.meetings.filter { $0.spaceID == spaceID }
      let spaceTasks = openTasks(in: spaceMeetings)

      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          header(space, meetingCount: spaceMeetings.count, taskCount: spaceTasks.count)

          Button {
            isAskingAI = true
          } label: {
            HStack {
              Image(icon: .sparkles)
              Text("このプロジェクトについて聞く")
                .font(.headline)
              Spacer()
              Image(icon: .arrowUpRight)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.plain)

          VStack(alignment: .leading, spacing: 12) {
            Text("進行中のタスク")
              .font(.title2.bold())
            if spaceTasks.isEmpty {
              Text("未完了のタスクはありません")
                .foregroundStyle(.secondary)
            } else {
              ForEach(spaceTasks) { task in
                TaskRow(task: task, showsSource: true)
              }
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("会話")
              .font(.title2.bold())
            ForEach(spaceMeetings) { meeting in
              NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
                MeetingRow(meeting: meeting)
              }
              .buttonStyle(.plain)

              if meeting.id != spaceMeetings.last?.id {
                Divider()
                  .padding(.leading, 52)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("チームで共有", icon: .personBadgePlus) {
            Task { await model.shareSpaceWithTeam(space.id) }
          }
          .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu("その他", icon: .ellipsis) {
            Button("名前を変更", icon: .pencil) { isRenaming = true }
            Button("削除", icon: .trash, role: .destructive) { isDeleting = true }
          }
        }
      }
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .space(space.id), askingQuestion: "このプロジェクトでまだ決まっていないことは？")
      }
      .sheet(isPresented: $isRenaming) {
        RenameSpaceSheet(space: space)
      }
      .confirmationDialog(
        "このプロジェクトを削除しますか？",
        isPresented: $isDeleting,
        titleVisibility: .visible
      ) {
        Button("削除", role: .destructive) {
          model.deleteSpace(space.id)
          dismiss()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("会話は削除されず、未分類に移動します。")
      }
    } else {
      ContentUnavailableView("プロジェクトが見つかりません", icon: .folderBadgeQuestionmark)
    }
  }

  private func header(_ space: MemoraSpace, meetingCount: Int, taskCount: Int) -> some View {
    HStack(spacing: 16) {
      Image(icon: space.icon)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 56, height: 56)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(space.name)
          .font(.title.bold())
        Text("\(meetingCount)件の会話 · \(taskCount)件のタスク")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 8)
  }

  private func openTasks(in spaceMeetings: [Meeting]) -> [MemoraTask] {
    let meetingIDs = Set(spaceMeetings.map(\.id))
    return model.tasks.filter { task in
      task.meetingID.map(meetingIDs.contains) == true && !task.isCompleted
    }
  }
}
