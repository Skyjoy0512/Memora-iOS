import Foundation

@main @MainActor
struct MCPOAuthLifecycleChecks {
  static func main() async throws {
    let browser = MCPOAuthBrowser()
    let server = MCPServerConfig()

    let oldDNS = Task { try await browser.authorize(server) }
    await waitUntil { MCPPublicAddressPolicy.pending.count == 1 }
    do {
      _ = try await browser.authorize(server)
      preconditionFailure("Second authorization started during validation")
    } catch MCPOAuthError.configuration { }
    browser.cancel()
    let afterDNS = Task { try await browser.authorize(server) }
    await waitUntil { MCPPublicAddressPolicy.pending.count == 2 }
    MCPPublicAddressPolicy.pending.removeFirst().resume()
    await requireCancellation(oldDNS)
    precondition(ASWebAuthenticationSession.created.isEmpty)
    MCPPublicAddressPolicy.pending.removeFirst().resume()
    await waitUntil { ASWebAuthenticationSession.created.count == 1 }
    let oldSheet = ASWebAuthenticationSession.created[0]
    afterDNS.cancel()
    await requireCancellation(afterDNS)

    let replacement = Task { try await browser.authorize(server) }
    await waitUntil { MCPPublicAddressPolicy.pending.count == 1 }
    MCPPublicAddressPolicy.pending.removeFirst().resume()
    await waitUntil { ASWebAuthenticationSession.created.count == 2 }
    precondition(oldSheet.cancelled)
    oldSheet.complete("stale-sheet")
    let newSheet = ASWebAuthenticationSession.created[1]
    newSheet.complete("current-sheet")
    await waitUntil { MCPOAuthClient.shared.pending.count == 1 }
    precondition(MCPOAuthClient.shared.pending[0].code == "current-sheet")
    browser.cancel()

    let afterExchange = Task { try await browser.authorize(server) }
    await waitUntil { MCPPublicAddressPolicy.pending.count == 1 }
    MCPOAuthClient.shared.finish()
    await requireCancellation(replacement)
    MCPPublicAddressPolicy.pending.removeFirst().resume()
    await waitUntil { ASWebAuthenticationSession.created.count == 3 }
    ASWebAuthenticationSession.created[2].complete("current-exchange")
    await waitUntil { MCPOAuthClient.shared.pending.count == 1 }
    MCPOAuthClient.shared.finish()
    let credential = try await afterExchange.value
    precondition(credential.code == "current-exchange")
    print("MCPOAuthLifecycleChecks: passed (production browser, overlapping validation, cancelled and late sheets, revoked exchange, current credential; framework/transport fixtures)")
  }

  private static func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
      if condition() { return }
      await Task.yield()
    }
    preconditionFailure("Expected callback was not reached")
  }

  private static func requireCancellation(_ operation: Task<MCPOAuthCredential, Error>) async {
    do {
      _ = try await operation.value
      preconditionFailure("Cancelled authorization returned a credential")
    } catch is CancellationError {
    } catch MCPOAuthError.cancelled {
    } catch { preconditionFailure("Unexpected authorization error: \(error)") }
  }
}

@MainActor
enum MCPPublicAddressPolicy {
  static var pending: [CheckedContinuation<Void, Never>] = []
  static func validateHost(_ host: String) async throws {
    await withCheckedContinuation { pending.append($0) }
  }
}

struct MCPServerConfig {
  var oauth: MCPOAuthSettings? = .init()
  var url = "https://example.test/mcp"
}
struct MCPOAuthSettings {
  var authorizationURL = "https://example.test/authorize"
  var clientID = "test"
  var scopes = "read"
}
struct MCPOAuthCredential: Sendable { var code: String }
enum MCPConnectionPolicy {
  static func endpoint(_ value: String) throws -> URL { URL(string: value)! }
}
enum MCPOAuthPolicy {
  static let redirectURI = URL(string: "memora://mcp")!
  static func validated(_ settings: MCPOAuthSettings) throws -> MCPOAuthSettings { settings }
  static func callbackCode(_ callback: URL, state: String) throws -> String { callback.lastPathComponent }
}
enum PKCE {
  static func makeVerifier(length: Int = 43) -> String { String(repeating: "x", count: length) }
  static func makeChallenge(from verifier: String) throws -> String { verifier }
}
struct OAuthAuthorizationCodeFlow {
  func extractCode(from callback: URL, expectedRedirectURI: URL, expectedState: String) throws -> String {
    callback.lastPathComponent
  }
}

@MainActor
final class MCPOAuthClient {
  static let shared = MCPOAuthClient()
  var pending: [(code: String, continuation: CheckedContinuation<MCPOAuthCredential, Never>)] = []
  func exchange(code: String, verifier: String, server: MCPServerConfig) async throws -> MCPOAuthCredential {
    await withCheckedContinuation { pending.append((code, $0)) }
  }
  func finish() {
    let entry = pending.removeFirst()
    entry.continuation.resume(returning: MCPOAuthCredential(code: entry.code))
  }
}

class UIWindow { }
typealias ASPresentationAnchor = UIWindow
class UIWindowScene {
  enum ActivationState { case foregroundActive }
  let activationState = ActivationState.foregroundActive
  let keyWindow: UIWindow? = UIWindow()
}
@MainActor
final class UIApplication {
  static let shared = UIApplication()
  let connectedScenes: [Any] = [UIWindowScene()]
}
@MainActor protocol ASWebAuthenticationPresentationContextProviding: AnyObject {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}
@MainActor
final class ASWebAuthenticationSession {
  static var created: [ASWebAuthenticationSession] = []
  weak var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
  var prefersEphemeralWebBrowserSession = false
  private(set) var cancelled = false
  private let completion: (URL?, Error?) -> Void
  init(url: URL, callbackURLScheme: String, completion: @escaping (URL?, Error?) -> Void) {
    self.completion = completion
    Self.created.append(self)
  }
  func start() -> Bool { true }
  func cancel() { cancelled = true }
  func complete(_ code: String) { completion(URL(string: "memora://mcp/\(code)")!, nil) }
}
