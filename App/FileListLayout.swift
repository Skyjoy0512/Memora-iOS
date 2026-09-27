import Foundation

/// How the files list is drawn. Persisted, so it survives a restart.
enum FileListLayout: String, CaseIterable, Identifiable {
  case card
  case list

  var id: Self { self }

  var label: String {
    switch self {
    case .card: "カード"
    case .list: "リスト"
    }
  }
}
