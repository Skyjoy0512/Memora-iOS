import AuthenticationServices
import UIKit

/// Owns the native sheet and its continuation together so cancellation cannot
/// leave a suspended login, or complete a later login with an old callback.
@MainActor
final class GmailAuthorizationSession {
  private var session: ASWebAuthenticationSession?
  private var continuation: CheckedContinuation<URL, Error>?
  private var identifier: UUID?
  private let presentation = GmailPresentationAnchor()

  func authorize(url: URL, scheme: String) async throws -> URL {
    try Task.checkCancellation()
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        cancel()
        identifier = id
        self.continuation = continuation
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
          Task { @MainActor in
            guard let self, self.identifier == id else { return }
            if let callback { self.finish(.success(callback)) }
            else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
              self.finish(.failure(GmailError.cancelled))
            } else { self.finish(.failure(GmailError.authorizationFailed)) }
          }
        }
        session.presentationContextProvider = presentation
        self.session = session
        if Task.isCancelled { cancel() }
        else if !session.start() { finish(.failure(GmailError.authorizationFailed)) }
      }
    } onCancel: {
      Task { @MainActor in
        guard self.identifier == id else { return }
        self.cancel()
      }
    }
  }

  func cancel() {
    let old = session
    finish(.failure(GmailError.cancelled))
    old?.cancel()
  }

  private func finish(_ result: Result<URL, Error>) {
    let pending = continuation
    continuation = nil
    identifier = nil
    session = nil
    pending?.resume(with: result)
  }
}

private final class GmailPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
      return scene?.keyWindow ?? ASPresentationAnchor()
    }
  }
}
