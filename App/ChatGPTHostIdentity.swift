import Foundation

struct ChatGPTHostIdentity: Equatable, Sendable {
  private static let keychainKey = "chatgpt.hostIdentity"
  private static let prefix = "urn:uuid:"

  var value: String

  static func current() -> ChatGPTHostIdentity {
    if let stored = KeychainStore.string(forKey: keychainKey),
       ChatGPTHostIdentity(value: stored).isWellFormed {
      return ChatGPTHostIdentity(value: stored)
    }

    let generated = ChatGPTHostIdentity(value: prefix + UUID().uuidString.lowercased())
    // The identity is still usable for this run when the keychain is unavailable.
    _ = KeychainStore.set(generated.value, forKey: keychainKey)
    return generated
  }

  var isWellFormed: Bool {
    guard value.hasPrefix(Self.prefix) else { return false }
    return UUID(uuidString: String(value.dropFirst(Self.prefix.count))) != nil
  }
}
