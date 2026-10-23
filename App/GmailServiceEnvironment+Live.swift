import Foundation

extension GmailServiceEnvironment {
  static var live: Self {
    let authorization = GmailAuthorizationSession()
    return Self(
      clientID: { GmailService.clientID },
      refreshToken: { KeychainStore.string(forKey: "gmail.refreshToken") },
      storeRefreshToken: { KeychainStore.set($0, forKey: "gmail.refreshToken") },
      email: { UserDefaults.standard.string(forKey: "memora.gmail.email") },
      storeEmail: { value in
        if let value { UserDefaults.standard.set(value, forKey: "memora.gmail.email") }
        else { UserDefaults.standard.removeObject(forKey: "memora.gmail.email") }
      },
      isLocallyDisconnected: { UserDefaults.standard.bool(forKey: "memora.gmail.disconnected") },
      setLocallyDisconnected: { UserDefaults.standard.set($0, forKey: "memora.gmail.disconnected") },
      authorize: { try await authorization.authorize(url: $0, scheme: $1) },
      cancelAuthorization: { authorization.cancel() },
      transport: { try await URLSession.shared.data(for: $0) },
      now: { .now }
    )
  }
}
