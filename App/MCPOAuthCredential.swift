import Foundation
import CoreFoundation

struct MCPOAuthCredential: Codable, Sendable {
  var identity: String
  var accessToken: String
  var refreshToken: String?
  var expiresAt: Date
  var scopes: Set<String>

  static func decodeResponse(_ data: Data, identity: String, requestedScopes: Set<String>,
                             previous: MCPOAuthCredential? = nil, now: Date = .now) throws -> MCPOAuthCredential {
    guard data.count <= 128 * 1024,
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          object["error"] == nil,
          let token = object["access_token"] as? String, !token.isEmpty,
          MCPConnectionPolicy.tokenIsValid(token), !token.contains(where: { $0.isWhitespace }),
          (object["token_type"] as? String)?.lowercased() == "bearer" else { throw MCPOAuthError.tokenResponse }
    let lifetime: Double
    if let raw = object["expires_in"] {
      guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw MCPOAuthError.tokenResponse }
      lifetime = number.doubleValue
    } else { lifetime = 3_600 }
    guard lifetime.isFinite, lifetime > 30, lifetime <= 31_536_000 else { throw MCPOAuthError.tokenResponse }
    let scopes: Set<String>
    if let raw = object["scope"] {
      guard let text = raw as? String else { throw MCPOAuthError.tokenResponse }
      scopes = try MCPOAuthPolicy.scopeSet(text)
    } else { scopes = previous?.scopes ?? requestedScopes }
    guard scopes.isSubset(of: requestedScopes) else { throw MCPOAuthError.tokenResponse }
    var refresh = previous?.refreshToken
    if let raw = object["refresh_token"] {
      guard let value = raw as? String, !value.isEmpty, MCPConnectionPolicy.tokenIsValid(value) else { throw MCPOAuthError.tokenResponse }
      refresh = value
    }
    return MCPOAuthCredential(identity: identity, accessToken: token, refreshToken: refresh,
      expiresAt: now.addingTimeInterval(lifetime), scopes: scopes)
  }
}
