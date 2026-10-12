import Foundation

extension MemoraModel {
  func workspaceItems(projectID: UUID?) -> [ProjectWorkspaceItem] {
    var items = projectSources.filter { projectID == nil || $0.projectID == projectID }.map(ProjectWorkspaceItem.source)
    if let projectID {
      items += meetings.filter { $0.spaceID == projectID }.map(ProjectWorkspaceItem.recording)
      items += documents.filter { $0.spaceID == projectID }.map(ProjectWorkspaceItem.document)
    }
    return items.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
  }
}
