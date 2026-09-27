import Foundation

/// The order the files list is shown in.
enum FileListSort: String, CaseIterable, Identifiable {
  case newest
  case oldest
  case longest

  var id: Self { self }

  var label: String {
    switch self {
    case .newest: "新しい順"
    case .oldest: "古い順"
    case .longest: "長い順"
    }
  }
}
