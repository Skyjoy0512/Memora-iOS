import Foundation

/// Platform and storage boundaries; tokens remain ephemeral outside Keychain.
@MainActor
struct GmailServiceEnvironment {
  var clientID: () -> String?
  var refreshToken: () -> String?
  var storeRefreshToken: (String?) -> Bool
  var email: () -> String?
  var storeEmail: (String?) -> Void
  var isLocallyDisconnected: () -> Bool
  var setLocallyDisconnected: (Bool) -> Void
  var authorize: (URL, String) async throws -> URL
  var cancelAuthorization: () -> Void
  var transport: (URLRequest) async throws -> (Data, URLResponse)
  var now: () -> Date
}
