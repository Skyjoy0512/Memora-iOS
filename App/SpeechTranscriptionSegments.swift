import Foundation

/// Turns a transcription result into a transcript line.
///
/// Nothing is merged, and nothing is dropped for being close in time or having
/// the same words as the line before: two people saying「はい」are two
/// utterances, and a phrase repeated later is said twice.
enum SpeechTranscriptionSegments {
  /// The line for one result, or nil when the result is not something to store
  /// (still volatile, or empty).
  static func segment(from update: SpeechTranscriptionUpdate) -> TranscriptSegment? {
    guard update.isFinal else { return nil }
    let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    return TranscriptSegment(
      id: UUID(),
      speaker: "話者",
      speakerIsCertain: false,
      timestamp: update.timestamp.isFinite ? update.timestamp : 0,
      text: text,
      endTime: update.endTime.flatMap { $0.isFinite && $0 > update.timestamp ? $0 : nil }
    )
  }
}
