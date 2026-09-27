import Foundation

/// The outcome of asking an engine: an answer, or the reason there is none.
enum AIAnswerResult {
  case answer(String)
  case failure(AIAnswerFailure)

  var text: String? {
    if case .answer(let text) = self { return text }
    return nil
  }

  var failure: AIAnswerFailure? {
    if case .failure(let reason) = self { return reason }
    return nil
  }
}
