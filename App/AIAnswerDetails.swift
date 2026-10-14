import Foundation

/// What actually produced an answer. Shown instead of an invented reasoning
/// trace, so the disclosure says where the answer came from.
struct AIAnswerDetails: Hashable, Codable, Sendable {
  /// The range the question was asked over, as the person sees it.
  var scopeLabel: String
  /// The engine that really ran.
  var engineLabel: String
  /// The provider's model name, when a cloud provider answered.
  var modelLabel: String?
  /// How many records were sent with the question.
  var sourceCount: Int
  var generatedAt: Date
}
