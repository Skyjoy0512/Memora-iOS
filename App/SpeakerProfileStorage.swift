import CryptoKit
import Foundation
import Security

struct SpeakerProfileStorage {
  let directory: URL
  private let defaults: UserDefaults
  private let service: String
  private let account = "encryption-key-v1"
  private let revokedKey = "memora.speakerProfileRevoked"

  init(directory: URL, defaults: UserDefaults, keychainService: String) {
    self.directory = directory
    self.defaults = defaults
    self.service = keychainService
  }
  private func file(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).encrypted") }
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account]
  }
  var hasStoredProfile: Bool {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
      .contains { $0.hasSuffix(".encrypted") }
  }

  func load(_ id: UUID) throws -> SpeakerProfile? {
    guard !defaults.bool(forKey: revokedKey), FileManager.default.fileExists(atPath: file(id).path) else { return nil }
    guard let bytes = try keyData() else { throw SpeakerProcessingFailure.profileUnavailable }
    let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file(id)))
    let decoded = try AES.GCM.open(sealed, using: SymmetricKey(data: bytes))
    let profile = try JSONDecoder().decode(SpeakerProfile.self, from: decoded)
    guard profile.id == id, profile.isValid else {
      throw SpeakerProcessingFailure.invalidEmbedding
    }
    return profile
  }

  func save(_ profile: SpeakerProfile) throws {
    guard profile.isValid else {
      throw SpeakerProcessingFailure.invalidEmbedding
    }
    let bytes: Data
    if let existing = try keyData() {
      bytes = existing
    } else {
      bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
      var attributes = query
      attributes[kSecValueData as String] = bytes
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
        throw SpeakerProcessingFailure.storageFailure
      }
    }
    var folder = directory
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    let sealed = try AES.GCM.seal(JSONEncoder().encode(profile), using: SymmetricKey(data: bytes))
    guard let combined = sealed.combined else { throw SpeakerProcessingFailure.storageFailure }
    try combined.write(to: file(profile.id), options: [.atomic, .completeFileProtection])
  }

  func activate() {
    defaults.set(false, forKey: revokedKey)
  }

  func delete() throws {
    defaults.set(true, forKey: revokedKey)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SpeakerProcessingFailure.storageFailure
    }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func removeUnused(keeping id: UUID) throws {
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
      guard name.hasSuffix(".encrypted"), let storedID = UUID(uuidString: String(name.dropLast(10))), storedID != id else { continue }
      try FileManager.default.removeItem(at: file(storedID))
    }
  }

  private func keyData() throws -> Data? {
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
      throw SpeakerProcessingFailure.profileUnavailable
    }
    return data
  }
}
