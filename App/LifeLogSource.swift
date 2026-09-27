import Foundation

enum LifeLogSource: String, Hashable, Codable {
  case iphone
  case omi
  case imported
  case automatic

  var label: String {
    switch self {
    case .iphone:
      "iPhone"
    case .omi:
      "Omi"
    case .imported:
      "取り込み"
    case .automatic:
      "自動"
    }
  }
}
