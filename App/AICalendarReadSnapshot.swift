import Foundation

/// Runtime grants are intentionally absent from Codable conversation snapshots and backups.
struct AICalendarReadSnapshot: Hashable, Sendable {
  var revision: UUID
  var readAt: Date
  var events: [AICalendarEventReference]

  var isValid: Bool {
    readAt.timeIntervalSince1970.isFinite && events.count <= 120
      && Set(events.map(\.id)).count == events.count && Set(events.map(\.sourceID)).count == events.count
      && events.allSatisfy(\.isValid)
  }

  func merging(_ incoming: [AICalendarEventReference], at date: Date) -> Self {
    var merged = events
    for var event in incoming.prefix(30) where event.isValid {
      if let index = merged.firstIndex(where: { $0.sourceID == event.sourceID }) {
        event.id = merged[index].id
        merged[index] = event
      } else if merged.count < 120 { merged.append(event) }
    }
    return Self(revision: revision, readAt: date, events: merged)
  }
}
