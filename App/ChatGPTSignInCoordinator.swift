import Foundation
import UIKit

/// How a ChatGPT sign-in ended.
enum ChatGPTSignInOutcome: Equatable, Sendable {
  /// The account is connected.
  case connected(subject: String, email: String?, name: String?, planUsage: Bool)
  /// The person closed the sign-in page.
  case cancelled
  /// The sign-in failed. The message is what the person is shown.
  case failed(message: String)
  /// The account was signed out. The flag says whether the remote session was
  /// revoked as well.
  case signedOut(revoked: Bool)
}

/// Runs a ChatGPT sign-in from the authorization request to the stored
/// credentials.
@MainActor
final class ChatGPTSignInCoordinator {
  /// The state of the sign-in this device holds.
  enum State: Equatable {
    /// No ChatGPT account is connected.
    case disconnected
    /// A sign-in is running.
    case connecting
    /// A ChatGPT account is connected.
    case connected
  }

  /// The current state.
  private(set) var state: State

  private var callbackServer: ChatGPTLoopbackCallbackServer?

  init() {
    state = ChatGPTCredentialStore.load() == nil ? .disconnected : .connected
  }

  /// The connection this device holds, when there is one.
  var connection: ChatGPTConnection? { ChatGPTCredentialStore.load() }

  /// Whether the connected account may use ChatGPT plan usage.
  var hasPlanUsage: Bool { ChatGPTCredentialStore.hasPlanUsage() }

  /// Signs in, opening the sign-in page in the browser.
  ///
  /// The flow is: bind the loopback listener, build the authorization request,
  /// open the browser, wait for the callback, exchange the code, verify the
  /// identity token and store the credentials.
  ///
  /// When an issued client ID is already stored, it is reused and the saved
  /// account's email is sent as `login_hint`. A callback that returns a
  /// different client ID than the stored one fails with
  /// `ChatGPTSignInError.accountMismatch`.
  ///
  /// An identity token whose subject differs from the stored one fails with
  /// `ChatGPTSignInError.accountMismatch`; the stored credentials are left
  /// untouched in that case.
  func signIn() async -> ChatGPTSignInOutcome {
    guard state != .connecting else { return .failed(message: ChatGPTSignInError.callbackFailed.localizedDescription) }
    let previous = ChatGPTCredentialStore.load()
    let storedClientID = previous?.clientID ?? ChatGPTCredentialStore.storedClientID()
    state = .connecting

    let server = ChatGPTLoopbackCallbackServer()
    callbackServer = server
    defer {
      server.cancel()
      if callbackServer === server {
        callbackServer = nil
        state = ChatGPTCredentialStore.load() == nil ? .disconnected : .connected
      }
    }

    do {
      // The redirect URI has to carry the port the listener actually bound,
      // so the listener is started before the request is built.
      let redirectURI = try await server.start()
      let request = try ChatGPTOAuthTransaction.makeAuthorizationRequest(
        clientID: storedClientID,
        hostID: ChatGPTHostIdentity.current().value,
        loginHint: previous?.email,
        redirectURI: redirectURI
      )
      server.expect(state: request.state)

      guard await UIApplication.shared.open(request.url) else {
        throw ChatGPTSignInError.browserUnavailable
      }
      let result = try await server.waitForCallback(state: request.state)

      if let callbackClientID = result.callback.clientID,
         let storedClientID,
         callbackClientID != storedClientID {
        throw ChatGPTSignInError.accountMismatch
      }
      let clientID = result.callback.clientID ?? storedClientID
      guard let clientID, ChatGPTOAuthTransaction.isIssuedClientID(clientID) else {
        throw ChatGPTSignInError.registrationIncomplete
      }
      if let previous, previous.clientID != clientID {
        throw ChatGPTSignInError.accountMismatch
      }

      let response = try await ChatGPTOAuthTransaction.exchange(
        code: result.callback.code,
        clientID: clientID,
        verifier: request.verifier,
        redirectURI: result.redirectURI
      )
      guard let idToken = response.idToken, !idToken.isEmpty else {
        throw ChatGPTSignInError.callbackFailed
      }

      let identity = try await ChatGPTIDTokenVerifier().verify(
        idToken: idToken,
        audience: clientID,
        nonce: request.nonce
      )
      if let previous, previous.subject != identity.subject {
        throw ChatGPTSignInError.accountMismatch
      }

      let saved = ChatGPTConnection(
        clientID: clientID,
        subject: identity.subject,
        email: identity.email,
        name: identity.name,
        scopes: response.scopes,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
        expiresAt: response.expiresAt,
        earliestRefreshAt: response.earliestRefreshAt,
        idToken: idToken
      )
      guard ChatGPTCredentialStore.save(saved) else {
        throw ChatGPTSignInError.callbackFailed
      }

      state = .connected
      return .connected(subject: identity.subject, email: identity.email, name: identity.name,
        planUsage: ChatGPTScope.includesPlanUsage(response.scopes))
    } catch {
      return Self.outcome(for: error)
    }
  }

  /// Cancels a running sign-in.
  func cancel() {
    callbackServer?.cancel()
    callbackServer = nil
    state = ChatGPTCredentialStore.load() == nil ? .disconnected : .connected
  }

  /// Refreshes the stored credentials when they are about to expire.
  ///
  /// Does nothing when there is no connection, when the access token is still
  /// valid for more than a minute, or when OpenAI has not yet allowed a
  /// refresh. Returns whether the connection was refreshed.
  func refreshIfNeeded() async -> Bool {
    guard state != .connecting, let stored = ChatGPTCredentialStore.load() else { return false }

    let now = Date()
    if stored.expiresAt.timeIntervalSince(now) > 60 { return true }
    guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else { return false }
    if let earliestRefreshAt = stored.earliestRefreshAt, earliestRefreshAt > now { return false }

    do {
      let response = try await ChatGPTOAuthTransaction.refresh(
        refreshToken: refreshToken,
        clientID: stored.clientID
      )
      var subject = stored.subject
      var email = stored.email
      var name = stored.name
      var idToken = stored.idToken
      if let returnedIDToken = response.idToken, !returnedIDToken.isEmpty {
        let identity = try await ChatGPTIDTokenVerifier().verify(
          idToken: returnedIDToken,
          audience: stored.clientID,
          nonce: nil
        )
        guard identity.subject == stored.subject else { return false }
        subject = identity.subject
        email = identity.email ?? email
        name = identity.name ?? name
        idToken = returnedIDToken
      }

      let renewed = ChatGPTConnection(
        clientID: stored.clientID,
        subject: subject,
        email: email,
        name: name,
        scopes: response.scopes,
        accessToken: response.accessToken,
        refreshToken: response.refreshToken ?? stored.refreshToken,
        expiresAt: response.expiresAt,
        earliestRefreshAt: response.earliestRefreshAt ?? stored.earliestRefreshAt,
        idToken: idToken
      )
      guard ChatGPTCredentialStore.save(renewed) else { return false }
      state = .connected
      return true
    } catch {
      return false
    }
  }

  /// Signs out: revokes the refresh token when there is one and removes the
  /// stored credentials.
  ///
  /// The local credentials are removed even when the revocation could not be
  /// confirmed, so the device stops using them. The outcome says whether the
  /// remote session was revoked.
  func signOut() async -> ChatGPTSignInOutcome {
    cancel()
    let stored = ChatGPTCredentialStore.load()
    var revoked = true
    if let stored, let refreshToken = stored.refreshToken, !refreshToken.isEmpty {
      do {
        try await ChatGPTOAuthTransaction.revoke(refreshToken: refreshToken, clientID: stored.clientID)
      } catch {
        revoked = false
      }
    }
    _ = ChatGPTCredentialStore.clear()
    state = .disconnected
    return .signedOut(revoked: revoked)
  }

  private static func outcome(for error: Error) -> ChatGPTSignInOutcome {
    if error is CancellationError { return .cancelled }
    if let loopback = error as? ChatGPTLoopbackError {
      switch loopback {
      case .cancelled:
        return .cancelled
      case .unavailable, .invalidCallback:
        return .failed(message: ChatGPTSignInError.callbackFailed.localizedDescription)
      }
    }
    if let signInError = error as? ChatGPTSignInError {
      if signInError == .cancelled { return .cancelled }
      return .failed(message: signInError.localizedDescription)
    }
    if error is ChatGPTTokenResponseError {
      return .failed(message: ChatGPTSignInError.invalidResponse.localizedDescription)
    }
    if let identityError = error as? ChatGPTIDTokenError {
      switch identityError {
      case .invalidToken:
        return .failed(message: ChatGPTSignInError.callbackFailed.localizedDescription)
      case .verificationUnavailable:
        return .failed(message: ChatGPTSignInError.serviceUnavailable.localizedDescription)
      }
    }
    return .failed(message: ChatGPTSignInError.callbackFailed.localizedDescription)
  }
}
