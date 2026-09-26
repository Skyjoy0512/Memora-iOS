import Foundation

/// A run of station passes close enough in time to read as one journey. Holds
/// the entries in time order so the view can name the stations.
struct JournalMovement: Identifiable, Hashable {
  var entries: [LifeLogEntry]

  /// The first record's id, so adding a later station does not make the row look
  /// like a different one and replay its entrance.
  var id: String { entries.first?.id.uuidString ?? "movement" }

  var start: Date { entries.first?.createdAt ?? .now }
  var end: Date { entries.last?.createdAt ?? start }
}
