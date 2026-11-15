import CryptoKit
import Foundation
import Synchronization

/// Discardable analysis in the existing SQLite store, outside backup documents.
/// A revoked lease cannot write results back after deletion or access changes.
actor SummaryArtifactCache {
  static let shared = SummaryArtifactCache(store: .shared)
  static let storageKey = "derived.summary.parts.v1"
  static let maximumEntries = 32
  static let maximumBytes = 4 * 1024 * 1024
  static let maximumEntryBytes = 256 * 1024
  static let retention: TimeInterval = 24 * 60 * 60

  private let store: LocalStore
  private let now: @Sendable () -> Date
  private nonisolated let epoch = Mutex(Generation())
  private nonisolated let potentialArtifacts = Mutex(true)
  private var accesses: [String: Date] = [:]
  private var resident: [Entry]?
  private var loadedRevision: String?
  private(set) var storageReads = 0
  private(set) var decodedBytes = 0

  init(store: LocalStore, now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  nonisolated var mayContainArtifacts: Bool { potentialArtifacts.withLock { $0 } }

  nonisolated func lease(ownerID: UUID? = nil) -> Lease {
    epoch.withLock { generation in
      if ownerID != nil {
        generation.hasUse = true
        potentialArtifacts.withLock { $0 = true }
      }
      return Lease(id: generation.id, owners: generation.owners.mapValues(\.id))
    }
  }

  struct Lease: Sendable {
    var id: UUID
    fileprivate var owners: [UUID: UUID]
  }

  /// Only the affected owner loses reuse. Source edits retain exact part keys;
  /// deletion/permissions remove that owner's data, including late worker writes.
  nonisolated func revoke(owners: Set<UUID>, retainingEntries: Bool = false, erasing: Bool = true) {
    guard !owners.isEmpty else { return }
    let generation = epoch.withLock { value in
      // Bound tombstones as well as payloads. The fallback is a full revocation.
      if Set(value.owners.keys).union(owners).count > 1_024 {
        value = Generation(acceptsPersisted: false)
      } else {
        for owner in owners {
          let canRetain = retainingEntries && (value.owners[owner]?.acceptsPersisted ?? true)
          value.owners[owner] = OwnerGeneration(acceptsPersisted: canRetain)
        }
      }
      return Lease(id: value.id, owners: value.owners.mapValues(\.id))
    }
    if erasing { Task { await eraseOwners(owners, retainingEntries: retainingEntries, lease: generation) } }
  }

  private func eraseOwners(_ owners: Set<UUID>, retainingEntries: Bool, lease: Lease) {
    epoch.withLock { generation in
      guard generation.id == lease.id else { return }
      let entries = load()
      let kept = entries.filter { entry in
        guard owners.contains(entry.ownerID) else { return generation.acceptsPersisted || entry.runEpoch == generation.id }
        guard lease.owners[entry.ownerID] == generation.owners[entry.ownerID]?.id else { return true }
        return generation.owners[entry.ownerID]?.acceptsPersisted == true || entry.ownerEpoch == generation.owners[entry.ownerID]?.id
      }
      if entries.count != kept.count { persist(kept) }
    }
  }

  nonisolated func revoke(erasing: Bool = true) {
    let generation = epoch.withLock { value in
      value = Generation(acceptsPersisted: false)
      potentialArtifacts.withLock { $0 = false }
      return value.id
    }
    // Revocation is synchronous. A delayed purge retains results authorized
    // under this new generation and cannot erase a later generation's work.
    if erasing { Task { await eraseRevoked(generation) } }
  }

  private func eraseRevoked(_ generation: UUID) {
    epoch.withLock { current in
      guard current.id == generation else { return }
      persist(load().filter { $0.runEpoch == generation })
    }
  }

  private func erase() { accesses = [:]; resident = nil; loadedRevision = nil; try? store.remove(Self.storageKey) }

  func clear() {
    epoch.withLock {
      $0 = Generation(acceptsPersisted: false)
      potentialArtifacts.withLock { $0 = false }
    }
    erase()
  }

  func retainOwners(_ owners: Set<UUID>, lease: Lease) {
    epoch.withLock { generation in
      guard generation.id == lease.id, lease.owners == generation.owners.mapValues(\.id) else { return }
      let entries = load()
      let kept = entries.filter { owners.contains($0.ownerID) && (generation.acceptsPersisted || $0.runEpoch == generation.id) }
      if !generation.hasUse { potentialArtifacts.withLock { $0 = !kept.isEmpty } }
      if kept.count != entries.count { persist(kept) }
    }
  }

  func read(_ key: String, lease: Lease) -> String? {
    epoch.withLock { generation in
      guard generation.id == lease.id, !Task.isCancelled else { return nil }
      let entries = load().filter { entry in
        guard generation.acceptsPersisted || entry.runEpoch == lease.id,
              lease.owners[entry.ownerID] == generation.owners[entry.ownerID]?.id else { return false }
        guard let owner = generation.owners[entry.ownerID] else { return true }
        return owner.acceptsPersisted || entry.ownerEpoch == owner.id
      }
      if !entries.isEmpty { potentialArtifacts.withLock { $0 = true } }
      guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
      // Touching LRU metadata must not rewrite a multi-megabyte blob for every
      // reused part. Access times are folded into the next artifact write.
      accesses[key] = now()
      return entries[index].text
    }
  }

  func write(_ text: String, key: String, ownerID: UUID, lease: Lease) {
    guard text.utf8.count <= Self.maximumEntryBytes, !text.isEmpty else { return }
    epoch.withLock { generation in
      guard generation.id == lease.id, !Task.isCancelled,
            lease.owners[ownerID] == generation.owners[ownerID]?.id else { return }
      generation.hasUse = true
      potentialArtifacts.withLock { $0 = true }
      var entries = load().filter { $0.key != key && (generation.acceptsPersisted || $0.runEpoch == lease.id) }
      accesses[key] = now()
      entries.append(Entry(key: key, ownerID: ownerID, runEpoch: lease.id, ownerEpoch: generation.owners[ownerID]?.id, text: text, checksum: Self.digest(text), createdAt: now(), accessedAt: now()))
      entries.sort { $0.accessedAt > $1.accessedAt }
      entries = Array(entries.prefix(Self.maximumEntries))
      while !entries.isEmpty, ((try? JSONEncoder().encode(entries).count) ?? Int.max) > Self.maximumBytes {
        entries.removeLast()
      }
      persist(entries)
    }
  }

  private func load() -> [Entry] {
    let beforeRevision = store.changeToken
    if let revision = beforeRevision, revision == loadedRevision, let resident {
      let instant = now()
      let kept = resident.filter { $0.createdAt <= instant && instant.timeIntervalSince($0.createdAt) < Self.retention }
      if kept.count != resident.count { persist(kept) }
      return touched(kept)
    }
    storageReads += 1
    guard case .data(let bytes) = store.readOutcome(Self.storageKey), bytes.count <= Self.maximumBytes,
          let values = try? JSONDecoder().decode([Entry].self, from: bytes), values.count <= Self.maximumEntries else { return [] }
    decodedBytes += bytes.count
    let instant = now()
    let kept = values.map { entry in
      var entry = entry
      entry.accessedAt = max(accesses[entry.key] ?? entry.accessedAt, entry.accessedAt)
      return entry
    }.filter {
      $0.key.utf8.count == 64 && $0.key.allSatisfy { "0123456789abcdef".contains($0) } &&
      $0.createdAt <= instant && instant.timeIntervalSince($0.createdAt) < Self.retention &&
      $0.accessedAt <= instant && $0.text.utf8.count <= Self.maximumEntryBytes && $0.checksum == Self.digest($0.text)
    }
    // An external writer between the read and token check must not label an
    // older payload with the newer revision.
    let afterRevision = store.changeToken
    guard beforeRevision != nil, beforeRevision == afterRevision else {
      resident = nil; loadedRevision = nil
      return []
    }
    resident = kept
    loadedRevision = afterRevision
    if kept.count != values.count { persist(kept) }
    return kept
  }

  private func touched(_ entries: [Entry]) -> [Entry] {
    entries.map { entry in
      var entry = entry
      entry.accessedAt = max(accesses[entry.key] ?? entry.accessedAt, entry.accessedAt)
      return entry
    }
  }

  private func persist(_ entries: [Entry]) {
    guard let data = try? JSONEncoder().encode(entries), data.count <= Self.maximumBytes else { return }
    let keys = Set(entries.map(\.key))
    accesses = accesses.filter { keys.contains($0.key) }
    do {
      try store.write(Self.storageKey, data: data)
      resident = nil
      loadedRevision = nil
    } catch {
      resident = nil
      loadedRevision = nil
    }
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private struct Generation: Sendable {
    var id = UUID()
    var acceptsPersisted = true
    var hasUse = false
    var owners: [UUID: OwnerGeneration] = [:]
  }

  private struct OwnerGeneration: Sendable {
    var id = UUID()
    var acceptsPersisted: Bool
  }

  private struct Entry: Codable {
    var key: String
    var ownerID: UUID
    var runEpoch: UUID
    var ownerEpoch: UUID?
    var text: String
    var checksum: String
    var createdAt: Date
    var accessedAt: Date
  }
}
