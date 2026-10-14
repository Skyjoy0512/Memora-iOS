import Foundation

extension Meeting {
  /// Metadata and processing status alone are not evidence of recording content.
  var hasReadableAIContent: Bool {
    if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || transcript.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return true }
    // Capture and recovery store processing hints in summary until it is made.
    switch status {
    case .ready, .partialFailure: break
    default: return false
    }
    return !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || [keyPoints, decisions, openQuestions].contains { values in
        values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      }
  }
}
