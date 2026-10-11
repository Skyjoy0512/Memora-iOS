import Foundation

/// One result from transcribing a saved audio file.
///
/// Saved audio is transcribed once, so a volatile result is not useful: it can
/// still change, and an empty volatile result withdraws the one before it.
/// `isFinal` marks the result of a phrase that has settled.
struct SpeechTranscriptionUpdate: Equatable {
  var text: String
  var timestamp: TimeInterval
  var isFinal: Bool
  var endTime: TimeInterval? = nil
}
