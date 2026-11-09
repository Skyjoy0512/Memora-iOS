import Foundation

struct MemoraSidebarAction: Equatable {
  var id: ObjectIdentifier
  var action: @MainActor () -> Void

  @MainActor func callAsFunction() { action() }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
