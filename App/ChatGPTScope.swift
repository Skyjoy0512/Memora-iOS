import Foundation

/// The permissions Memora asks OpenAI for when someone signs in with
/// ChatGPT.
enum ChatGPTScope {
  /// Identifies the account.
  static let openID = "openid"
  /// Grants the account's display name.
  static let profile = "profile"
  /// Grants the account's email address.
  static let email = "email"
  /// Grants a refresh token, so the session can be renewed.
  static let offlineAccess = "offline_access"
  /// Grants calling the API on the person's behalf.
  static let resourceInvoke = "resource.invoke"
  /// Grants ChatGPT plan usage. Only eligible plans get this one.
  static let planUsage = ChatGPTTokenResponse.planUsageScope

  /// Every scope Memora asks for, in one string.
  static let all = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

  /// Whether granted scopes include ChatGPT plan usage.
  static func includesPlanUsage(_ granted: [String]) -> Bool {
    granted.contains(planUsage)
  }
}
