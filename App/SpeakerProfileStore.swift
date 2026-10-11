import Foundation

enum SpeakerProfileStore {
  private static let storage = SpeakerProfileStorage(
    directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SpeakerProfiles", isDirectory: true),
    defaults: .standard, keychainService: "app.memora.speaker-profile")

  static var hasStoredProfile: Bool { storage.hasStoredProfile }
  static func load(_ id: UUID) throws -> SpeakerProfile? { try storage.load(id) }
  static func save(_ profile: SpeakerProfile) throws { try storage.save(profile) }
  static func activate() { storage.activate() }
  static func delete() throws { try storage.delete() }
  static func removeUnused(keeping id: UUID) throws { try storage.removeUnused(keeping: id) }
}
