import AuthenticationServices
import UIKit
import MCP

@MainActor
final class MCPOAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  private weak var window: UIWindow?
  private var continuation: CheckedContinuation<URL, Error>?
  private var authorizationID: UUID?

  func authorize(_ server: MCPServerConfig) async throws -> MCPOAuthCredential {
    try Task.checkCancellation()
    guard authorizationID == nil, let settings = server.oauth else { throw MCPOAuthError.configuration }
    let id = UUID()
    authorizationID = id
    defer { if authorizationID == id { authorizationID = nil } }
    let validated = try MCPOAuthPolicy.validated(settings)
    let endpoint = try MCPConnectionPolicy.endpoint(validated.authorizationURL)
    guard let host = endpoint.host else { throw MCPOAuthError.configuration }
    try await MCPPublicAddressPolicy.validateHost(host)
    try checkAuthorization(id)
    let verifier = PKCE.makeVerifier()
    let state = PKCE.makeVerifier(length: 48)
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw MCPOAuthError.configuration }
    components.queryItems = [
      .init(name: "response_type", value: "code"), .init(name: "client_id", value: validated.clientID),
      .init(name: "redirect_uri", value: MCPOAuthPolicy.redirectURI.absoluteString),
      .init(name: "resource", value: try MCPConnectionPolicy.endpoint(server.url).absoluteString),
      .init(name: "code_challenge", value: try PKCE.makeChallenge(from: verifier)),
      .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
      .init(name: "scope", value: validated.scopes)
    ]
    guard let authorizationURL = components.url else { throw MCPOAuthError.configuration }
    let callback = try await present(authorizationURL, authorizationID: id)
    try checkAuthorization(id)
    _ = try MCPOAuthPolicy.callbackCode(callback, state: state)
    let code: String
    do {
      code = try OAuthAuthorizationCodeFlow().extractCode(from: callback,
        expectedRedirectURI: MCPOAuthPolicy.redirectURI, expectedState: state)
    } catch { throw MCPOAuthError.callback }
    let credential = try await MCPOAuthClient.shared.exchange(code: code, verifier: verifier, server: server)
    try checkAuthorization(id)
    return credential
  }

  private func checkAuthorization(_ id: UUID) throws {
    try Task.checkCancellation()
    guard authorizationID == id else { throw CancellationError() }
  }

  private func present(_ url: URL, authorizationID id: UUID) async throws -> URL {
    window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?.keyWindow
    guard window != nil else { throw MCPOAuthError.configuration }
    return try await withTaskCancellationHandler {
      try checkAuthorization(id)
      return try await withCheckedThrowingContinuation { value in
        continuation = value
        let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "memora") { [weak self] callback, _ in
          Task { @MainActor in
            guard let self, self.authorizationID == id else { return }
            self.finish(callback.map { .success($0) } ?? .failure(MCPOAuthError.cancelled))
          }
        }
        browser.presentationContextProvider = self
        browser.prefersEphemeralWebBrowserSession = true
        session = browser
        if !browser.start() { finish(.failure(MCPOAuthError.configuration)) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self, self.authorizationID == id else { return }
        self.cancel()
      }
    }
  }

  func cancel() {
    let old = session
    authorizationID = nil
    finish(.failure(MCPOAuthError.cancelled))
    old?.cancel()
  }

  private func finish(_ result: Result<URL, Error>) {
    let pending = continuation
    continuation = nil; session = nil
    pending?.resume(with: result)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    window ?? ASPresentationAnchor()
  }
}
