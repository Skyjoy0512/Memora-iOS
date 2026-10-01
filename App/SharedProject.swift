import Foundation

/// A project a teammate shared, with the records it held when they last
/// published it.
struct SharedProject: Identifiable, Hashable {
  var id: String
  var name: String
  var icon: MemoraIcon
  var ownerName: String
  var updatedAt: Date
  var records: [SharedRecord]
}
