import Foundation

/// View lifetime can end during scrolling; an answer's introduction must not
/// restart with it. IDs alone are retained, without answer text or user data.
@MainActor
enum AIResponseIntroductionRegistry {
  private static var introduced: Set<UUID> = []
  private static var order: [UUID] = []

  static func contains(_ id: UUID) -> Bool { introduced.contains(id) }

  static func claim(_ id: UUID) -> Bool {
    guard introduced.insert(id).inserted else { return false }
    order.append(id)
    if order.count > 128 { introduced.remove(order.removeFirst()) }
    return true
  }
}
