import Foundation

/// The provider and model a cloud request goes to. Read once when a request
/// starts, so a settings change mid-answer cannot mix two providers.
struct LLMSelection: Hashable, Sendable {
  var provider: LLMProvider
  var modelID: String
  var displayName: String? = nil
  /// A server other than the provider's own, such as Memora Intelligence.
  var endpoint: URL? = nil
  /// The keychain item holding the credential for `endpoint`.
  var credentialAccount: String? = nil
  var supportsToolCalling = true

  var baseURL: URL { endpoint ?? provider.baseURL }
  var keychainAccount: String { credentialAccount ?? provider.keychainAccount }
  var isMemoraIntelligence: Bool { credentialAccount == MemoraIntelligence.tokenAccount }

  /// The name shown in an answer's details: the suggested name when the id is
  /// one of the suggestions, otherwise the id itself.
  var modelLabel: String {
    if endpoint != nil, let displayName { return displayName }
    let name = displayName ?? provider.suggestedModels.first { $0.id == modelID }?.name ?? modelID
    return "\(provider.label) · \(name)"
  }
}
