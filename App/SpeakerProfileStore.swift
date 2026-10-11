import CryptoKit
import Foundation
import Security

enum SpeakerProfileStore {
  private static let service = "app.memora.speaker-profile"
  private static let account = "encryption-key-v1"
  private static let revokedKey = "memora.speakerProfileRevoked"

  private static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SpeakerProfiles", isDirectory: true)
  }
  private static func file(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).encrypted") }
  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account]
  }
  static var hasStoredProfile: Bool {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
      .contains { $0.hasSuffix(".encrypted") }
  }

  static func load(_ id: UUID) throws -> SpeakerProfile? {
    guard !UserDefaults.standard.bool(forKey: revokedKey), FileManager.default.fileExists(atPath: file(id).path) else { return nil }
    guard let bytes = try keyData() else { throw SpeakerProcessingFailure.profileUnavailable }
    let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file(id)))
    let decoded = try AES.GCM.open(sealed, using: SymmetricKey(data: bytes))
    let profile = try JSONDecoder().decode(SpeakerProfile.self, from: decoded)
    guard profile.id == id, profile.embeddingData.count == profile.embeddingDimension,
          profile.embeddingDimension == 256, profile.embeddingData.allSatisfy(\.isFinite),
          SpeakerEmbeddingMath.cosine(profile.embeddingData, profile.embeddingData) != nil else {
      throw SpeakerProcessingFailure.invalidEmbedding
    }
    return profile
  }

  static func save(_ profile: SpeakerProfile) throws {
    guard profile.isCurrentUser, profile.embeddingDimension == 256,
          profile.embeddingData.count == profile.embeddingDimension,
          SpeakerEmbeddingMath.cosine(profile.embeddingData, profile.embeddingData) != nil else {
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

  static func activate() {
    UserDefaults.standard.set(false, forKey: revokedKey)
  }

  static func delete() throws {
    UserDefaults.standard.set(true, forKey: revokedKey)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SpeakerProcessingFailure.storageFailure
    }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  static func removeUnused(keeping id: UUID) throws {
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
      guard name.hasSuffix(".encrypted"), let storedID = UUID(uuidString: String(name.dropLast(10))), storedID != id else { continue }
      try FileManager.default.removeItem(at: file(storedID))
    }
  }

  private static func keyData() throws -> Data? {
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
