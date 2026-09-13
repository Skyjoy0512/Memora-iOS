import Foundation

/// A signed-in Memora account.
///
/// Signing in is optional. Recording, transcription, and organizing all work
/// without an account; the account only adds sync and Plus.
struct MemoraAccount: Codable, Hashable {
  var displayName: String
  var email: String
  var provider: AuthProvider
  var createdAt: Date
}

enum AuthProvider: String, Codable, Hashable, CaseIterable, Identifiable {
  case apple
  case google
  case email

  var id: Self { self }

  var label: String {
    switch self {
    case .apple:
      "Apple"
    case .google:
      "Google"
    case .email:
      "メールアドレス"
    }
  }

  var signInTitle: String {
    switch self {
    case .apple:
      "Appleでサインイン"
    case .google:
      "Googleでサインイン"
    case .email:
      "メールアドレスで続ける"
    }
  }

  var symbol: String {
    switch self {
    case .apple:
      "apple.logo"
    case .google:
      "g.circle"
    case .email:
      "envelope"
    }
  }
}
