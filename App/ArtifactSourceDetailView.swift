import SwiftUI

struct ArtifactSourceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var target: ArtifactSourceTarget
  var workspaceID: String?

  var body: some View {
    if model.canOpenArtifactSource(target, workspaceID: workspaceID) {
      switch target {
      case .record(.meeting(let id)):
        NavigationStack {
          MeetingDetailView(meetingID: id, showsLocalPlaybackBar: true)
            .navigationDestination(for: LibraryRoute.self) { LibraryDestinationView(route: $0) }
            .toolbar { closingToolbar }
        }
      case .record(.journal(let id)):
        LifeLogEntryDetailView(entryID: id)
      case .record(.task(let id)):
        if let task = model.tasks.first(where: { $0.id == id }) { TaskEditView(task: task) }
      case .record(.person(let id)):
        NavigationStack {
          PersonDetailView(personID: id)
            .navigationDestination(for: LibraryRoute.self) { LibraryDestinationView(route: $0) }
            .toolbar { closingToolbar }
        }
      case .projectFile(let id):
        NavigationStack {
          ProjectSourceDetailView(sourceID: id)
            .navigationDestination(for: LibraryRoute.self) { LibraryDestinationView(route: $0) }
            .toolbar { closingToolbar }
        }
      }
    } else {
      ContentUnavailableView("元の情報を開けません", icon: .docQuestionmark,
        description: Text("削除・移動またはワークスペースの変更を確認してください。"))
    }
  }

  private var closingToolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
    }
  }
}
