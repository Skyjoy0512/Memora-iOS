import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  var spaceID: UUID
  @State private var isAskingAI = false

  var body: some View {
    if let space = model.space(id: spaceID) {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          header(space)

          Button {
            isAskingAI = true
          } label: {
            HStack {
              Image(systemName: "sparkles")
              Text("このプロジェクトについて聞く")
                .font(.headline)
              Spacer()
              Image(systemName: "arrow.up.right")
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
              Divider()
                .padding(.leading, 52)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .space(space.id), suggestedQuestion: "このプロジェクトでまだ決まっていないことは？")
      }
    } else {
      ContentUnavailableView("プロジェクトが見つかりません", systemImage: "folder.badge.questionmark")
    }
  }

  private func header(_ space: MemoraSpace) -> some View {
    HStack(spacing: 16) {
      Image(systemName: space.symbol)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 56, height: 56)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(space.name)
          .font(.title.bold())
        Text("\(spaceMeetings.count)件の会話 · \(spaceTasks.count)件のタスク")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 8)
  }

  private var spaceMeetings: [Meeting] {
    model.meetings.filter { $0.spaceID == spaceID }
  }

  private var spaceTasks: [MemoraTask] {
    let meetingIDs = Set(spaceMeetings.map(\.id))
    return model.tasks.filter { meetingIDs.contains($0.meetingID) && !$0.isCompleted }
  }
}
