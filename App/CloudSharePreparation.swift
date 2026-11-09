import Foundation

struct CloudSharePreparation {
  var id = UUID()
  var workspaceID: String?
  var generation: UUID
  var snapshot: TeamShareSnapshot
  var ownerName: String
}
