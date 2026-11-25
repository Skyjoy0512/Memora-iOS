import Foundation
import Security

/// Keeps credentials in the device's Keychain.
enum KeychainStore {
  private static let service = "app.memora.keys"
  private static let mutationLock = NSRecursiveLock()

  @discardableResult
  static func set(_ value: String?, forKey key: String) -> Bool {
    mutationLock.lock()
    defer { mutationLock.unlock() }

    let match = query(for: key)
    if let value, !value.isEmpty { return write(Data(value.utf8), matching: match) }
    let status = SecItemDelete(match as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  static func string(forKey key: String) -> String? {
    mutationLock.lock()
    defer { mutationLock.unlock() }

    // Recheck availability on every read so a device lock takes effect and a
    // temporary failure does not hide the item after unlocking.
    var match = query(for: key)
    match[kSecReturnData as String] = true
    match[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(match as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
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

  static func write(
    _ data: Data,
    matching query: [String: Any],
    update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate,
    add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
  ) -> Bool {
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    // Commit protection and data together, leaving the old value intact on
    // failure. An add is needed only for an item that does not exist yet.
    let status = update(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }
    let addStatus = add(query.merging(attributes) { _, new in new } as CFDictionary)
    if addStatus == errSecDuplicateItem {
      return update(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
    return addStatus == errSecSuccess
  }

  private static func query(for key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
  }
}
