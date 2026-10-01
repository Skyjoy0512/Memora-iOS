import Foundation

/// A team the person belongs to. Its records live in the cloud, shared by
/// every member, unlike the personal workspace, which stays on the device.
struct TeamWorkspace: Identifiable, Hashable, Codable {
  enum Role: String, Codable {
    /// Created the team and manages its members.
    case owner
    /// Sees and edits the team's records.
    case member

    var label: String {
      switch self {
      case .owner: "オーナー"
      case .member: "メンバー"
      }
    }
  }

  var id: String
  var name: String
  var role: Role
}
