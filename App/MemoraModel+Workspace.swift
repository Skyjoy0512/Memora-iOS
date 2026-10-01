import Foundation

extension MemoraModel {
  /// The workspace on screen. A remembered team that is no longer in the list
  /// falls back to the personal workspace.
  var currentWorkspace: Workspace {
    guard let currentTeamID,
          let team = teamWorkspaces.first(where: { $0.id == currentTeamID }) else {
      return .personal
    }
    return .team(team)
  }

  var workspaces: [Workspace] {
    [.personal] + teamWorkspaces.map(Workspace.team)
  }

  func selectWorkspace(_ workspace: Workspace) {
    switch workspace {
    case .personal:
      currentTeamID = nil
    case .team(let team):
      currentTeamID = team.id
    }
  }

  /// Re-reads the person's teams. With no cloud connected the list stays empty.
  func refreshTeams() async {
    guard let teams = try? await teamBackend.teams(), teams != teamWorkspaces else { return }
    teamWorkspaces = teams
  }

  /// Creates a team and opens it. Throws with a reason the sheet shows.
  func createTeam(named name: String) async throws {
    guard hasTeamPlan else { throw TeamBackendError.requiresTeamPlan }
    let team = try await teamBackend.createTeam(named: name)
    addAndOpen(team)
  }

  /// Joins the team behind an invite code and opens it.
  func joinTeam(inviteCode: String) async throws {
    let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { throw TeamBackendError.invalidInviteCode }
    let team = try await teamBackend.joinTeam(inviteCode: code)
    addAndOpen(team)
  }

  private func addAndOpen(_ team: TeamWorkspace) {
    if !teamWorkspaces.contains(where: { $0.id == team.id }) {
      teamWorkspaces.append(team)
    }
    currentTeamID = team.id
  }
}
