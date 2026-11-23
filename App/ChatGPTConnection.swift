import Foundation

/// The ChatGPT connection this device holds. The credentials are secrets, so
/// they live in the keychain and never in UserDefaults or on disk.
struct ChatGPTConnection: Equatable, Sendable {
  /// The client ID OpenAI issued for this app.
  var clientID: String
  /// The verified subject of the account.
  var subject: String
  /// The account's email address, when the token carried one.
  var email: String?
  /// The account's display name, when the token carried one.
  var name: String?
  /// The permissions OpenAI granted.
  var scopes: [String]
  /// The access token.
  var accessToken: String
  /// The refresh token, when one was granted.
  var refreshToken: String?
  /// When the access token expires.
  var expiresAt: Date
  /// When OpenAI allows the refresh token to be used, when it said so.
  var earliestRefreshAt: Date?
  /// The issued identity token, kept so a later refresh can re-check it.
  var idToken: String?
}
