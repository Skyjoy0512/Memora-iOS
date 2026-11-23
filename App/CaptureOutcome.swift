import Foundation

/// What one intake did.
enum CaptureOutcome: Hashable, Sendable {
  /// The intent became a new record.
  case imported(UUID)
  /// The same content was already stored, so nothing new was added.
  case duplicate(UUID)
  /// The intent could not be used. The text says why.
  case refused(String)
}
