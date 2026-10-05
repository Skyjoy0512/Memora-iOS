import Foundation

/// The Hindsight memory server Ask AI personalizes from
/// (github.com/vectorize-io/hindsight). A setting, so it lives in
/// UserDefaults; the token, when the server needs one, is in the keychain.
struct HindsightConfig: Codable, Equatable {
  var baseURL = ""
  var bankID = "memora"
  var isEnabled = false

  /// The keychain account for the server's API key.
  static let tokenAccount = "hindsight.token"

  var isConfigured: Bool {
    !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !bankID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
