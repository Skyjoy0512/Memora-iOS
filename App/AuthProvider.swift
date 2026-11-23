import Foundation

enum AuthProvider: String, Codable, Hashable, CaseIterable, Identifiable {
  case apple
  case google
  case email
  case chatGPT

  var id: Self { self }

  var label: String {
    switch self {
    case .apple:
      "Apple"
    case .google:
      "Google"
    case .email:
      "メールアドレス"
    case .chatGPT:
      "ChatGPT"
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
    case .chatGPT:
      "ChatGPTで続ける"
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
    case .chatGPT:
      .sparkles
    }
  }
}
