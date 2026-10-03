import Foundation

/// Memora's own cloud AI for people without a key: an OpenAI-compatible
/// endpoint on Memora's server, which holds the DeepSeek key, meters every
/// request in credits and refuses one the plan cannot pay for. The app never
/// holds a provider key for it.
///
/// The build needs the server's URL under the Info.plist key
/// `MemoraIntelligenceURL`, and the server issues the access token kept under
/// `tokenAccount`. Without them the app says the service is not connected.
enum MemoraIntelligence {
  static let tokenAccount = "memora.intelligence.token"
  static let modelID = "memora-standard"

  static var endpoint: URL? {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "MemoraIntelligenceURL") as? String,
          let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme == "https" else { return nil }
    return url
  }

  static var isConfigured: Bool {
    endpoint != nil
  }

  /// What a request to Memora Intelligence is sent as: the OpenAI-compatible
  /// path, pointed at Memora's server with Memora's token.
  static var selection: LLMSelection {
    LLMSelection(
      provider: .deepSeek,
      modelID: modelID,
      displayName: "Memora Intelligence",
      endpoint: endpoint ?? URL(string: "https://invalid.memora.local")!,
      credentialAccount: tokenAccount
    )
  }

  /// One credit is this much AI cost at the provider's list price.
  static let dollarsPerCredit = 0.005

  /// Rough credits for one action, to show before it is used. The server
  /// charges what was actually used.
  static let typicalCosts: [(action: String, credits: String)] = [
    ("Ask AIで1回質問", "約1"),
    ("60分の会議を要約", "約3"),
    ("エージェントに1回依頼", "約8")
  ]
}
