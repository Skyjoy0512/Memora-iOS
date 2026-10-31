import Foundation

/// Pasted text has no verified media timeline. Keep its order without inventing times or speakers.
enum VideoTranscript {
  static let maximumCharacters = 200_000

  static func segments(_ text: String) -> [TranscriptSegment]? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= maximumCharacters else { return nil }
    var remaining = text[...]
    var segments: [TranscriptSegment] = []
    // Bound each segment for the small on-device context and the cloud part scheduler.
    while !remaining.isEmpty {
      let end = remaining.index(remaining.startIndex, offsetBy: 1_200, limitedBy: remaining.endIndex) ?? remaining.endIndex
      segments.append(TranscriptSegment(id: UUID(), speaker: "字幕・文字起こし", speakerIsCertain: false,
        timestamp: 0, text: String(remaining[..<end])))
      remaining = remaining[end...]
    }
    return segments
  }
}
