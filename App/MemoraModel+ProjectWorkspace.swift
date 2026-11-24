import Foundation

extension MemoraModel {
  func projectTasks(projectID: UUID, includeCompleted: Bool = false) -> [MemoraTask] {
    guard space(id: projectID) != nil else { return [] }
    let recordIDs = Set(meetings.filter { $0.spaceID == projectID }.map(\.id))
    return ProjectTaskList.select(from: tasks, recordIDs: recordIDs, includeCompleted: includeCompleted)
  }

  func workspaceItems(projectID: UUID?) -> [ProjectWorkspaceItem] {
    (workspaceFiles(projectID: projectID) + workspaceSources(projectID: projectID))
      .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }

  /// Recordings and generated documents filed in a project. Sources live in
  /// their own tab, so nothing is copied between the two lists.
  func workspaceFiles(projectID: UUID?) -> [ProjectWorkspaceItem] {
    var items: [ProjectWorkspaceItem] = []
    if let projectID {
      items += meetings.filter { $0.spaceID == projectID }.map(ProjectWorkspaceItem.recording)
      items += documents.filter { $0.spaceID == projectID }.map(ProjectWorkspaceItem.document)
    }
    return items.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }

  func workspaceSources(projectID: UUID?) -> [ProjectWorkspaceItem] {
    projectSources
      .filter { projectID == nil || $0.projectID == projectID }
      .map(ProjectWorkspaceItem.source)
      .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }

  /// Photos the project's records hold, newest first. The record owns the file;
  /// this is only a reading of it, so a removed record takes its photos along.
  func projectPhotos(projectID: UUID) -> [ProjectPhoto] {
    var photos: [ProjectPhoto] = []
    for record in meetings where record.spaceID == projectID {
      for name in record.photoFileNames ?? [] {
        photos.append(ProjectPhoto(name: name, date: record.createdAt,
                                   recordID: record.id, recordTitle: record.displayTitle))
      }
    }
    return photos.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }
}
