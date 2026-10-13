import Foundation

struct MCPOAuthSettings: Codable, Hashable, Sendable {
  var clientID = ""
  var authorizationURL = ""
  var tokenURL = ""
  var scopes = ""
}
