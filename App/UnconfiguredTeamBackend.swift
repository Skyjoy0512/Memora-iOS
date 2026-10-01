import Foundation

/// Stands in until the cloud service is connected. It refuses every request
/// with a reason instead of pretending a team was created or joined.
struct UnconfiguredTeamBackend: TeamBackend {
  func teams() async throws -> [TeamWorkspace] {
    []
  }

  func createTeam(named name: String) async throws -> TeamWorkspace {
    throw TeamBackendError.notConfigured
  }

  func joinTeam(inviteCode: String) async throws -> TeamWorkspace {
    throw TeamBackendError.notConfigured
  }
}
