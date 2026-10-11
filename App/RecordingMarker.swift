import Foundation

struct RecordingMarker: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var timestamp: TimeInterval
  var title = "重要な場面"

  var displayTitle: String {
    let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "重要な場面" : text
  }

  static func adding(at timestamp: TimeInterval, to markers: [RecordingMarker]) -> [RecordingMarker]? {
    guard timestamp.isFinite, timestamp >= 0, timestamp < Double(Int.max),
          !markers.contains(where: { abs($0.timestamp - timestamp) < 1 }) else { return nil }
    return markers + [RecordingMarker(timestamp: timestamp)]
  }

  static func validated(_ markers: [RecordingMarker], duration: TimeInterval) -> [RecordingMarker] {
    guard duration.isFinite, duration >= 0, duration < Double(Int.max) else { return [] }
    var seen: Set<UUID> = []
    return markers.filter {
      $0.timestamp.isFinite && $0.timestamp >= 0 && $0.timestamp <= duration && seen.insert($0.id).inserted
    }.sorted {
      $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp
    }
  }
}
