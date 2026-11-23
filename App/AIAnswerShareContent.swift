import Foundation

/// One answer prepared for the share card shown after a screenshot.
struct AIAnswerShareContent: Identifiable {
  var id = UUID()
  var question: String
  var answer: String
  var createdAt: Date
}
