import Foundation

struct LifeLogEntry: Identifiable, Hashable {
  var id: UUID
  var createdAt: Date
  var title: String
  var summary: String
  var source: LifeLogSource
  var meetingID: UUID?
}

enum LifeLogSource: String, Hashable {
  case iphone
  case omi
  case imported

  var label: String {
    switch self {
    case .iphone:
      "iPhone"
    case .omi:
      "Omi"
    case .imported:
      "取り込み"
    }
  }
}
