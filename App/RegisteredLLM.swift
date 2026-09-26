import Foundation

/// A saved choice, not a provider catalog entry. Names belong to the user.
struct RegisteredLLM: Identifiable, Codable, Hashable {
  var id: UUID = UUID()
  var provider: LLMProvider
  var modelID: String
  var name: String

  var selection: LLMSelection {
    LLMSelection(provider: provider, modelID: modelID, displayName: name)
  }
}
