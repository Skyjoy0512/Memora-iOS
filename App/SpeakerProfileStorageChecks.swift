#if DEBUG
import Foundation
import Security

enum SpeakerProfileStorageChecks {
  static func run() throws {
    let namespace = "app.memora.speaker-profile.check.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: namespace) else { throw SpeakerProcessingFailure.storageFailure }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(namespace, isDirectory: true)
    let storage = SpeakerProfileStorage(directory: directory, defaults: defaults, keychainService: namespace)
    defer {
      try? storage.delete()
      defaults.removePersistentDomain(forName: namespace)
    }
    func require(_ condition: Bool, _ detail: String) throws {
      if !condition { throw NSError(domain: "SpeakerProfileStorageChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: detail]) }
    }
    let quality = VoiceQualityMetadata(sampleDuration: 20, speechDuration: 15, peak: 0.5,
      rootMeanSquare: 0.1, clippedSampleCount: 0, detectedSpeakerCount: 1)
    let profile = SpeakerProfile(embeddingData: [Float](repeating: 1 / 16, count: 256),
      embeddingModelID: "synthetic-storage-check", embeddingModelVersion: "v1", embeddingDimension: 256,
      enrollmentDuration: 20, consentAt: .now, qualityMetadata: quality, enrollmentSamples: [quality])
    let file = directory.appendingPathComponent("\(profile.id.uuidString).encrypted")
    try require(try storage.load(profile.id) == nil, "missing profile must remain missing")
    try storage.save(profile)
    storage.activate()
    let reloaded = SpeakerProfileStorage(directory: directory, defaults: defaults, keychainService: namespace)
    try require(try reloaded.load(profile.id) == profile, "encrypted round trip")
    let firstCiphertext = try Data(contentsOf: file)
    try require(!firstCiphertext.contains(Data(profile.embeddingModelID.utf8)), "plaintext in encrypted file")
    try storage.save(profile)
    let secondCiphertext = try Data(contentsOf: file)
    try require(firstCiphertext != secondCiphertext, "fresh AES-GCM nonce")
    try require(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true,
      "profile folder must be excluded from backup")
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    let protection = attributes[.protectionKey]
    #if targetEnvironment(simulator)
    if protection != nil {
      try require(protection as? String == FileProtectionType.complete.rawValue
        || protection as? FileProtectionType == .complete, "unexpected simulator protection attribute")
    }
    #else
    try require(protection as? String == FileProtectionType.complete.rawValue
      || protection as? FileProtectionType == .complete,
      "complete file protection: \(String(describing: protection))")
    #endif
    let keyQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: namespace, kSecAttrAccount as String: "encryption-key-v1",
      kSecReturnAttributes as String: true]
    var keyAttributes: CFTypeRef?
    try require(SecItemCopyMatching(keyQuery as CFDictionary, &keyAttributes) == errSecSuccess, "keychain key present")
    try require((keyAttributes as? [String: Any])?[kSecAttrAccessible as String] as? String
      == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String, "device-only unlocked key")

    var damaged = secondCiphertext
    damaged[damaged.count - 1] ^= 1
    try damaged.write(to: file, options: [.atomic, .completeFileProtection])
    var rejectsTampering = false
    do { _ = try reloaded.load(profile.id) } catch { rejectsTampering = true }
    try require(rejectsTampering, "AES-GCM authentication")
    try storage.save(profile)
    let otherID = UUID()
    let otherFile = directory.appendingPathComponent("\(otherID.uuidString).encrypted")
    try Data(contentsOf: file).write(to: otherFile, options: [.atomic, .completeFileProtection])
    var rejectsWrongID = false
    do { _ = try storage.load(otherID) } catch { rejectsWrongID = true }
    try require(rejectsWrongID, "profile ID cannot be substituted")
    try storage.removeUnused(keeping: profile.id)
    try require(!FileManager.default.fileExists(atPath: otherFile.path), "old profile cleanup")
    var invalid = profile
    invalid.embeddingData = [Float](repeating: 0, count: 256)
    var rejectsInvalid = false
    do { try storage.save(invalid) } catch { rejectsInvalid = true }
    try require(rejectsInvalid, "invalid embedding rejected")
    try require(try storage.load(profile.id) == profile, "invalid save must preserve existing profile")

    let deleteKeyQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: namespace, kSecAttrAccount as String: "encryption-key-v1"]
    try require(SecItemDelete(deleteKeyQuery as CFDictionary) == errSecSuccess, "remove isolated test key")
    var rejectsMissingKey = false
    do { _ = try reloaded.load(profile.id) }
    catch SpeakerProcessingFailure.profileUnavailable { rejectsMissingKey = true }
    try require(rejectsMissingKey, "missing key must not return a plaintext fallback")
    try storage.save(profile)
    try require(try reloaded.load(profile.id) == profile, "re-enrollment with fresh key")

    defaults.set(true, forKey: "memora.speakerProfileRevoked")
    try storage.save(profile)
    try require(try reloaded.load(profile.id) == nil, "save must not reactivate revoked profile")
    storage.activate()
    try require(try reloaded.load(profile.id) == profile, "activation after reference commit")
    try storage.delete()
    try require(!storage.hasStoredProfile && !FileManager.default.fileExists(atPath: directory.path), "delete files")
    try require(SecItemCopyMatching(keyQuery as CFDictionary, &keyAttributes) == errSecItemNotFound, "delete key")
    try require(try reloaded.load(profile.id) == nil, "deleted profile stays revoked")
    try storage.delete()
  }
}
#endif
