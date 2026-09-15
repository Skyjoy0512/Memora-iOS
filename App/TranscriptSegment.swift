import Foundation

struct TranscriptSegment: Identifiable, Hashable, Codable {
  var id: UUID
  var speaker: String
  var speakerIsCertain: Bool
  var timestamp: TimeInterval
  var text: String
}
