import Foundation

enum TaskProgress: String, Codable, CaseIterable, Identifiable {
  case notStarted
  case inProgress
  case waiting

  var id: String { rawValue }

  var label: String {
    switch self {
    case .notStarted: "着手前"
    case .inProgress: "進行中"
    case .waiting: "相手待ち"
    }
  }
}
