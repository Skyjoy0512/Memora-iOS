import Foundation

/// A run of station passes close enough in time to read as one journey. Holds
/// the entries in time order so the view can name the stations.
struct JournalMovement: Identifiable, Hashable {
  var entries: [LifeLogEntry]

  var id: String {
    entries.map { $0.id.uuidString }.joined(separator: "-")
  }

  var start: Date { entries.first?.createdAt ?? .now }
  var end: Date { entries.last?.createdAt ?? start }
}
