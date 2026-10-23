import Foundation

/// The exact record/task snapshot reviewed before an external save starts.
@MainActor
struct NotionExportContext {
  let meeting: Meeting
  let tasks: [MemoraTask]
  private let generation: UUID
  private let scope: AIChatScope

  init?(in model: MemoraModel, meetingID: UUID, scope: AIChatScope) {
    guard let meeting = MemoraModel.meetings(in: scope, from: model.meetings).first(where: { $0.id == meetingID }) else { return nil }
    self.meeting = meeting
    self.scope = scope
    tasks = model.permittedTasks(for: .cloudAI, scope: scope).filter { $0.meetingID == meetingID }
    generation = model.aiWorkspaceGeneration
    guard isCurrent(in: model) else { return nil }
  }

  func isCurrent(in model: MemoraModel) -> Bool {
    !Task.isCancelled && model.currentTeamID == nil && !model.isRestoring && !model.isStoreProtected &&
      model.aiWorkspaceGeneration == generation &&
      MemoraModel.meetings(in: scope, from: model.meetings).contains(meeting) &&
      RecordAccessPolicy.allows(meeting.effectivePrivacy, purpose: .cloudAI) &&
      tasks.allSatisfy { task in model.tasks.contains(task) && model.allowsTaskAccess(task, purpose: .cloudAI) }
  }
}
