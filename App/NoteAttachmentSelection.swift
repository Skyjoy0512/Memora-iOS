import Foundation

/// Ordered multi-selection for attaching existing sources to a note. The array
/// is the source of truth so the saved order is the order the person tapped;
/// toggling an already selected source off and on moves it to the end.
struct NoteAttachmentSelection: Equatable, Sendable {
  static let maximumCount = 64
  private(set) var ids: [UUID] = []

  var isEmpty: Bool { ids.isEmpty }

  func contains(_ id: UUID) -> Bool { ids.contains(id) }

  mutating func toggle(_ id: UUID, maximumCount: Int = Self.maximumCount) {
    if let index = ids.firstIndex(of: id) {
      ids.remove(at: index)
    } else if ids.count < maximumCount {
      ids.append(id)
    }
  }
}
