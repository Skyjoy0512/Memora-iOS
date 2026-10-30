import Foundation

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

  var symbol: MemoraIcon {
    switch self {
    case .apple:
      .key
    case .google:
      .gCircle
    case .email:
      .envelope
    }
  }
}
