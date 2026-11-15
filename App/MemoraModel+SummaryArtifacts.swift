import CryptoKit
import Foundation

extension MemoraModel {
  func summaryArtifactScope(ownerID: UUID, privacy: RecordPrivacy, llm: LLMSelection, projectID: UUID? = nil) -> SummaryArtifactScope? {
    guard currentTeamID == nil, !isStoreProtected, !isRestoring,
          let credential = KeychainStore.string(forKey: llm.keychainAccount), !credential.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let privacyData = try? encoder.encode(privacy) else { return nil }
    return SummaryArtifactScope(ownerID: ownerID, workspace: "personal", account: account?.email ?? "device-local",
      privacy: SHA256.hash(data: privacyData).map { String(format: "%02x", $0) }.joined(), credentialHash: SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined(), projectID: projectID)
  }

  func invalidateSummaryArtifacts(previous: [Meeting], cache: SummaryArtifactCache = .shared) {
    guard cache.mayContainArtifacts else { return }
    let current = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var removed: Set<UUID> = [], edited: Set<UUID> = []
    for old in previous {
      guard let new = current[old.id] else { removed.insert(old.id); continue }
      if old.title != new.title || old.createdAt != new.createdAt || old.duration != new.duration ||
          old.spaceID != new.spaceID || old.participantIDs != new.participantIDs || old.effectivePrivacy != new.effectivePrivacy {
        removed.insert(old.id)
      } else if old.transcript != new.transcript { edited.insert(old.id) }
    }
    cache.revoke(owners: removed, erasing: !isStoreProtected)
    cache.revoke(owners: edited, retainingEntries: true, erasing: !isStoreProtected)
  }

  func invalidateSummaryArtifacts(previous: [ProjectSource], cache: SummaryArtifactCache = .shared) {
    guard cache.mayContainArtifacts else { return }
    let current = Dictionary(projectSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let affected = Set(previous.compactMap { old -> UUID? in
      guard let new = current[old.id] else { return old.id }
      return old.extractedTextReference != new.extractedTextReference || old.contentFingerprint != new.contentFingerprint ||
        old.privacy != new.privacy || old.projectID != new.projectID || old.title != new.title ||
        old.originalURL != new.originalURL || old.textCoverage != new.textCoverage || old.errorInformation != new.errorInformation
        ? old.id : nil
    })
    cache.revoke(owners: affected, erasing: !isStoreProtected)
  }
}
