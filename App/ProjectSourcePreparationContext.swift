import Foundation

/// A URL or file reference alone cannot detect a move, privacy edit, replacement
/// or A → B → A workspace transition while extraction is suspended.
struct ProjectSourcePreparationContext {
  var source: ProjectSource
  private var project: MemoraSpace?
  private var generation: UUID

  @MainActor init?(_ id: UUID, in model: MemoraModel) {
    guard !Task.isCancelled, !model.isRestoring, !model.isStoreProtected,
          model.currentTeamID == nil, let source = model.source(id: id) else { return nil }
    let project = source.projectID.flatMap { model.space(id: $0) }
    guard source.projectID == nil || project != nil else { return nil }
    self.source = source
    self.project = project
    generation = model.aiWorkspaceGeneration
  }

  @MainActor func isCurrent(in model: MemoraModel, allowsCancellation: Bool = false) -> Bool {
    (allowsCancellation || !Task.isCancelled) && !model.isRestoring && !model.isStoreProtected &&
      model.currentTeamID == nil && generation == model.aiWorkspaceGeneration &&
      model.source(id: source.id) == source &&
      source.projectID.flatMap({ model.space(id: $0) }) == project
  }
}
