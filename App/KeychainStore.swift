import Foundation
import Security

/// Stores API keys in the keychain so they never touch UserDefaults or disk.
///
/// Reads are cached in memory: screens ask whether a key is set while drawing,
/// and a keychain query each time is needlessly slow.
enum KeychainStore {
  private static let service = "app.memora.keys"
  private static let lock = NSLock()
  /// A key mapped to its value, or to `nil` when it is known to be absent.
  private static var cache: [String: String?] = [:]

  static func set(_ value: String?, forKey key: String) {
    let stored = (value?.isEmpty == false) ? value : nil

    lock.lock()
    cache[key] = stored
    lock.unlock()

    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(base as CFDictionary)

    guard let stored, let data = stored.data(using: .utf8) else { return }

    var attributes = base
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(attributes as CFDictionary, nil)
  }

  static func string(forKey key: String) -> String? {
    lock.lock()
    if let cached = cache[key] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let value = readFromKeychain(key)

    lock.lock()
    cache[key] = value
    lock.unlock()

    return value
  }

  static func has(_ key: String) -> Bool {
    string(forKey: key) != nil
  }

  private static func readFromKeychain(_ key: String) -> String? {
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
}
