import Foundation

/// The provider and model a cloud request goes to. Read once when a request
/// starts, so a settings change mid-answer cannot mix two providers.
struct LLMSelection: Hashable, Sendable {
  var provider: LLMProvider
  var modelID: String

  /// The name shown in an answer's details: the suggested name when the id is
  /// one of the suggestions, otherwise the id itself.
  var modelLabel: String {
    let name = provider.suggestedModels.first { $0.id == modelID }?.name ?? modelID
    return "\(provider.label) · \(name)"
  }
}
