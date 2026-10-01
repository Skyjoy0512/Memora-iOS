import Foundation

/// Where the app is working: the personal space kept on this device, or a
/// team whose records are shared through the cloud — the way a design tool
/// separates a personal account from a business team.
enum Workspace: Hashable, Identifiable {
  case personal
  case team(TeamWorkspace)

  var id: String {
    switch self {
    case .personal: "personal"
    case .team(let team): "team.\(team.id)"
    }
  }

  var title: String {
    switch self {
    case .personal: "個人"
    case .team(let team): team.name
    }
  }

  var icon: MemoraIcon {
    switch self {
    case .personal: .iphone
    case .team: .person2
    }
  }

  /// Where its records are kept, said plainly so the difference is clear.
  var storageDescription: String {
    switch self {
    case .personal: "この端末だけに保存"
    case .team: "チームのクラウドで共有"
    }
  }
}
