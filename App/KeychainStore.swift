import Foundation
import Security

/// Stores API keys in the keychain so they never touch UserDefaults or disk.
///
/// Reads are cached in memory: screens ask whether a key is set while drawing,
/// and a keychain query each time is needlessly slow.
enum KeychainStore {
  private static let service = "app.memora.keys"
  private static let lock = NSLock()
  private static let mutationLock = NSRecursiveLock()
  /// A key mapped to its value, or to `nil` when it is known to be absent.
  private static var cache: [String: String?] = [:]

  /// Writes a secret. The in-memory cache is only updated once the keychain
  /// write succeeded, so a failed save never looks like a success.
  @discardableResult
  static func set(_ value: String?, forKey key: String) -> Bool {
    mutationLock.lock()
    defer { mutationLock.unlock() }
    let stored = (value?.isEmpty == false) ? value : nil

    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]

    let succeeded: Bool

    if let stored, let data = stored.data(using: .utf8) {
      // Update in place so a failure leaves the previous secret untouched.
      let updateStatus = SecItemUpdate(
        base as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )

      if updateStatus == errSecItemNotFound {
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        succeeded = SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
      } else {
        succeeded = updateStatus == errSecSuccess
      }
    } else {
      let deleteStatus = SecItemDelete(base as CFDictionary)
      succeeded = deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
    }

    guard succeeded else { return false }

    lock.lock()
    cache[key] = stored
    lock.unlock()
    return true
  }

  static func string(forKey key: String) -> String? {
    mutationLock.lock()
    defer { mutationLock.unlock() }
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

  static func replaceIfUnchanged(_ value: String, expected: String, forKey key: String) -> Bool {
    mutationLock.lock()
    defer { mutationLock.unlock() }
    guard string(forKey: key) == expected else { return false }
    return set(value, forKey: key)
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
