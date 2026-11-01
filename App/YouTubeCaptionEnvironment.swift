import Foundation

@MainActor
struct YouTubeCaptionEnvironment {
  var clientID: () -> String?
  var refreshToken: () -> String?
  var storeRefreshToken: (String?) -> Bool
  var isDisconnected: () -> Bool
  var setDisconnected: (Bool) -> Void
  var authorize: (URL, String) async throws -> URL
  var cancelAuthorization: () -> Void
  var transport: (URLRequest) async throws -> (status: Int, body: Data)
  var now: () -> Date
}
