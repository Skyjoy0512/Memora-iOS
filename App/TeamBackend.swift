import Foundation

/// The cloud service behind team workspaces: accounts, teams, invitations,
/// and the records members share. The app talks to this protocol only, so the
/// service (Firebase is planned) is plugged in in one place.
protocol TeamBackend: Sendable {
  /// The teams the signed-in person belongs to.
  func teams() async throws -> [TeamWorkspace]
  /// Creates a team with the person as its owner.
  func createTeam(named name: String) async throws -> TeamWorkspace
  /// Joins the team an invite code was issued for.
  func joinTeam(inviteCode: String) async throws -> TeamWorkspace
  func taskBoard(teamID: String) async throws -> TeamTaskBoardSnapshot
  func updateTask(_ task: MemoraTask, teamID: String, expectedRevision: String) async throws -> TeamTaskBoardSnapshot
}

extension TeamBackend {
  func taskBoard(teamID: String) async throws -> TeamTaskBoardSnapshot {
    throw TeamBackendError.notConfigured
  }
  func updateTask(_ task: MemoraTask, teamID: String, expectedRevision: String) async throws -> TeamTaskBoardSnapshot {
    throw TeamBackendError.notConfigured
  }
}
