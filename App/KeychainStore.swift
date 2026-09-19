import Foundation
import Security

/// Stores API keys in the keychain so they never touch UserDefaults or disk.
enum KeychainStore {
  private static let service = "app.memora.keys"

  static func set(_ value: String?, forKey key: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(base as CFDictionary)

    guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }

    var attributes = base
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(attributes as CFDictionary, nil)
  }

  static func string(forKey key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func has(_ key: String) -> Bool {
    string(forKey: key) != nil
  }
}
