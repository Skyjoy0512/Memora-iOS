import Foundation

/// Captured before a picker or file transfer starts. Team identity alone misses
/// A → B → A transitions, and a project ID alone misses replacement or edits.
struct LocalImportContext {
  private var project: MemoraSpace?
  private var generation: UUID
  var projectID: UUID? { project?.id }

  @MainActor init?(projectID: UUID? = nil, in model: MemoraModel) {
    guard !Task.isCancelled, model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected else { return nil }
    project = projectID.flatMap { model.space(id: $0) }
    guard projectID == nil || project != nil else { return nil }
    generation = model.aiWorkspaceGeneration
  }

  @MainActor func isCurrent(in model: MemoraModel, allowsRemovedProject: Bool = false) -> Bool {
    guard !Task.isCancelled, model.currentTeamID == nil, !model.isRestoring, !model.isStoreProtected,
          model.aiWorkspaceGeneration == generation else { return false }
    guard let project else { return true }
    let current = model.space(id: project.id)
    return current == project || (allowsRemovedProject && current == nil)
  }
}
