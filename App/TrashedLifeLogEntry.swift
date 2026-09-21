import Foundation

/// A journal entry moved to the trash, kept so it can be put back.
struct TrashedLifeLogEntry: Identifiable, Codable, Hashable {
  var id: UUID { entry.id }
  var entry: LifeLogEntry
  var deletedAt: Date
}

extension TrashedLifeLogEntry {
  /// Whole days left before the entry is removed for good.
  func daysRemaining(from now: Date = .now) -> Int {
    let remaining = max(0, deletedAt.addingTimeInterval(TrashedRecord.lifetime).timeIntervalSince(now))
    return Int(ceil(remaining / (24 * 60 * 60)))
  }
}
