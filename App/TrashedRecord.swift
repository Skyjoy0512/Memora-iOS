import Foundation

/// A record moved to the trash, kept together with what pointed at it so it can
/// be put back exactly as it was.
struct TrashedRecord: Identifiable, Codable, Hashable {
  /// The record's id, so a restore can be addressed by the same value.
  var id: UUID { meeting.id }
  var meeting: Meeting
  var tasks: [MemoraTask]
  var lifeLogEntries: [LifeLogEntry]
  var deletedAt: Date
}

extension TrashedRecord {
  /// How long a trashed record stays recoverable.
  static let lifetime: TimeInterval = 30 * 24 * 60 * 60

  /// Whole days left before the record is removed for good.
  func daysRemaining(from now: Date = .now) -> Int {
    let remaining = max(0, deletedAt.addingTimeInterval(Self.lifetime).timeIntervalSince(now))
    return Int(ceil(remaining / (24 * 60 * 60)))
  }
}
