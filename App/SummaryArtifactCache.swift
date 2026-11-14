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

  init(store: LocalStore, now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  nonisolated var mayContainArtifacts: Bool { potentialArtifacts.withLock { $0 } }

  nonisolated func lease(ownerID: UUID? = nil) -> UUID {
    epoch.withLock { generation in
      if ownerID != nil {
        generation.hasUse = true
        potentialArtifacts.withLock { $0 = true }
      }
      return generation.id
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

  private func erase() { accesses = [:]; try? store.remove(Self.storageKey) }

  func clear() {
    epoch.withLock {
      $0 = Generation(acceptsPersisted: false)
      potentialArtifacts.withLock { $0 = false }
    }
    erase()
  }

  func retainOwners(_ owners: Set<UUID>, lease: UUID) {
    epoch.withLock { generation in
      guard generation.id == lease else { return }
      let entries = load()
      let kept = entries.filter { owners.contains($0.ownerID) && (generation.acceptsPersisted || $0.runEpoch == generation.id) }
      if !generation.hasUse { potentialArtifacts.withLock { $0 = !kept.isEmpty } }
      if kept.count != entries.count { persist(kept) }
    }
  }

  func read(_ key: String, lease: UUID) -> String? {
    epoch.withLock { generation in
      guard generation.id == lease, !Task.isCancelled else { return nil }
      let entries = load().filter { generation.acceptsPersisted || $0.runEpoch == lease }
      if !entries.isEmpty { potentialArtifacts.withLock { $0 = true } }
      guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
      // Touching LRU metadata must not rewrite a multi-megabyte blob for every
      // reused part. Access times are folded into the next artifact write.
      accesses[key] = now()
      return entries[index].text
    }
  }

  func write(_ text: String, key: String, ownerID: UUID, lease: UUID) {
    guard text.utf8.count <= Self.maximumEntryBytes, !text.isEmpty else { return }
    epoch.withLock { generation in
      guard generation.id == lease, !Task.isCancelled else { return }
      generation.hasUse = true
      potentialArtifacts.withLock { $0 = true }
      var entries = load().filter { $0.key != key && (generation.acceptsPersisted || $0.runEpoch == lease) }
      accesses[key] = now()
      entries.append(Entry(key: key, ownerID: ownerID, runEpoch: lease, text: text, checksum: Self.digest(text), createdAt: now(), accessedAt: now()))
      entries.sort { $0.accessedAt > $1.accessedAt }
      entries = Array(entries.prefix(Self.maximumEntries))
      while !entries.isEmpty, ((try? JSONEncoder().encode(entries).count) ?? Int.max) > Self.maximumBytes {
        entries.removeLast()
      }
      persist(entries)
    }
  }

  private func load() -> [Entry] {
    guard case .data(let bytes) = store.readOutcome(Self.storageKey), bytes.count <= Self.maximumBytes,
          let values = try? JSONDecoder().decode([Entry].self, from: bytes), values.count <= Self.maximumEntries else { return [] }
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
    if kept.count != values.count { persist(kept) }
    return kept
  }

  private func persist(_ entries: [Entry]) {
    guard let data = try? JSONEncoder().encode(entries), data.count <= Self.maximumBytes else { return }
    let keys = Set(entries.map(\.key))
    accesses = accesses.filter { keys.contains($0.key) }
    try? store.write(Self.storageKey, data: data)
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private struct Generation: Sendable {
    var id = UUID()
    var acceptsPersisted = true
    var hasUse = false
  }

  private struct Entry: Codable {
    var key: String
    var ownerID: UUID
    var runEpoch: UUID
    var text: String
    var checksum: String
    var createdAt: Date
    var accessedAt: Date
  }
}
