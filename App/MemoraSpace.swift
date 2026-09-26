import Foundation

struct MemoraSpace: Identifiable, Hashable, Codable {
  var id: UUID
  var name: String
  var symbol: String
}

extension MemoraSpace {
  /// The stored name resolved to an icon; a name this build does not know
  /// falls back to a folder instead of drawing nothing.
  var icon: MemoraIcon {
    MemoraIcon(rawValue: symbol) ?? .folder
  }
}
