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
      let updateStatus = SecItemUpdate(
        base as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )

      if updateStatus == errSecItemNotFound {
        succeeded = add(data, base: base)
      } else if updateStatus == errSecSuccess {
        // SecItemUpdate keeps the attribute an older build stored, so the
        // matching item is replaced to adopt the current protection.
        let deleteStatus = SecItemDelete(base as CFDictionary)
        if deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound {
          succeeded = add(data, base: base)
        } else {
          succeeded = false
        }
      } else {
        succeeded = false
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

  private static func add(_ data: Data, base: [String: Any]) -> Bool {
    var attributes = base
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
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
