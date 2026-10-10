import Foundation

extension MemoraModel {
  func loadTeamTaskBoard(teamID: String) async throws -> TeamTaskBoardSnapshot {
    guard hasTeamPlan, currentWorkspace.id == "team.\(teamID)" else { throw TeamBackendError.requiresTeamPlan }
    let snapshot = try await teamBackend.taskBoard(teamID: teamID)
    guard currentWorkspace.id == "team.\(teamID)", hasTeamPlan,
          snapshot.teamID == teamID, snapshot.isValid else { throw TeamBackendError.invalidTaskBoard }
    return snapshot
  }

  func moveTeamTask(_ task: MemoraTask, to column: TaskBoardColumn, snapshot: TeamTaskBoardSnapshot) async throws -> TeamTaskBoardSnapshot {
    guard hasTeamPlan, currentWorkspace.id == "team.\(snapshot.teamID)",
          snapshot.tasks.contains(task), snapshot.isValid else { throw TeamBackendError.invalidTaskBoard }
    let updated = try await teamBackend.updateTask(column.applying(to: task), teamID: snapshot.teamID, expectedRevision: snapshot.revision)
    guard currentWorkspace.id == "team.\(snapshot.teamID)", hasTeamPlan,
          updated.teamID == snapshot.teamID, updated.isValid else { throw TeamBackendError.invalidTaskBoard }
    return updated
  }
}
