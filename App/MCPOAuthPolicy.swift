import Foundation
import CryptoKit

enum MCPOAuthPolicy {
  static var redirectURI: URL { URL(string: "memora://oauth/mcp")! }

  static func validated(_ settings: MCPOAuthSettings) throws -> MCPOAuthSettings {
    guard !settings.clientID.isEmpty, settings.clientID.utf8.count <= 512,
          !settings.clientID.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
          MCPConnectionPolicy.tokenIsValid(settings.clientID) else { throw MCPOAuthError.configuration }
    var result = settings
    result.authorizationURL = try MCPConnectionPolicy.endpoint(settings.authorizationURL).absoluteString
    result.tokenURL = try MCPConnectionPolicy.endpoint(settings.tokenURL).absoluteString
    guard URL(string: result.authorizationURL)?.host == URL(string: result.tokenURL)?.host else { throw MCPOAuthError.configuration }
    let scopes = try scopeSet(settings.scopes)
    guard !scopes.isEmpty, scopes.count <= 16 else { throw MCPOAuthError.configuration }
    result.scopes = scopes.sorted().joined(separator: " ")
    return result
  }

  static func scopeSet(_ text: String) throws -> Set<String> {
    guard text.utf8.count <= 2_048, text.utf8.allSatisfy({ $0 == 32 || $0 == 33 || (35...91).contains($0) || (93...126).contains($0) }) else { throw MCPOAuthError.configuration }
    return Set(text.split(separator: " ").map(String.init))
  }

  static func identity(endpoint: String, settings: MCPOAuthSettings) throws -> String {
    let validated = try validated(settings)
    let resource = try MCPConnectionPolicy.endpoint(endpoint)
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let bytes = try encoder.encode(validated) + Data(resource.absoluteString.utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  static func callbackCode(_ callback: URL, state: String) throws -> String {
    guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
          parts.scheme == redirectURI.scheme, parts.host == redirectURI.host, parts.path == redirectURI.path,
          parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
          callback.absoluteString.utf8.count <= 16_384 else { throw MCPOAuthError.callback }
    let items = parts.queryItems ?? []
    guard !items.contains(where: { $0.name == "error" }),
          items.filter({ $0.name == "state" }).count == 1,
          items.filter({ $0.name == "code" }).count == 1,
          items.first(where: { $0.name == "state" })?.value == state,
          let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
          MCPConnectionPolicy.tokenIsValid(code) else { throw MCPOAuthError.callback }
    return code
  }

  static func form(_ values: [String: String]) -> Data {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let text = values.keys.sorted().map { key in
      key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + values[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
    }.joined(separator: "&")
    return Data(text.utf8)
  }
}
