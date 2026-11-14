import Foundation
import Synchronization

@main enum SummaryArtifactCacheChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("records.sqlite")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    try store.write("existing-record", data: Data("unchanged".utf8))
    let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
    let cache = SummaryArtifactCache(store: store, now: { clock.withLock { $0 } })
    let owner = UUID(), key = String(repeating: "a", count: 64)
    let lease = cache.lease()
    await cache.write("validated part", key: key, ownerID: owner, lease: lease)
    let hit = await cache.read(key, lease: lease)
    precondition(hit == "validated part")
    // A separate store must be prepared, just as RecordStore is at app startup.
    let restartStore = LocalStore(fileURL: url)
    try restartStore.prepare()
    let restarted = SummaryArtifactCache(store: restartStore, now: { clock.withLock { $0 } })
    let restored = await restarted.read(key, lease: restarted.lease())
    precondition(restored == "validated part")
    cache.revoke(erasing: false)
    let revokedNewLease = await cache.read(key, lease: cache.lease())
    precondition(revokedNewLease == nil, "A new lease revived a revoked entry before erasure")
    await cache.write("stale worker", key: key, ownerID: owner, lease: lease)
    let stale = await cache.read(key, lease: lease)
    precondition(stale == nil)
    await cache.clear()
    let newLease = cache.lease()
    for number in 0..<40 {
      let entryKey = String(format: "%064x", number)
      await cache.write("part \(number)", key: entryKey, ownerID: owner, lease: newLease)
      clock.withLock { $0 = $0.addingTimeInterval(1) }
    }
    guard case .data(let entries) = store.readOutcome(SummaryArtifactCache.storageKey),
          let rows = try JSONSerialization.jsonObject(with: entries) as? [[String: Any]] else {
      preconditionFailure("No persistent cache")
    }
    precondition(rows.count == SummaryArtifactCache.maximumEntries && entries.count <= SummaryArtifactCache.maximumBytes)
    let evicted = await cache.read(String(format: "%064x", 0), lease: newLease)
    precondition(evicted == nil)
    await cache.write(String(repeating: "x", count: SummaryArtifactCache.maximumEntryBytes + 1), key: key, ownerID: owner, lease: newLease)
    let oversized = await cache.read(key, lease: newLease)
    precondition(oversized == nil)
    await cache.retainOwners([])
    let removed = await cache.read(String(format: "%064x", 39), lease: newLease)
    precondition(removed == nil)
    await cache.write("expires", key: key, ownerID: owner, lease: newLease)
    clock.withLock { $0 = $0.addingTimeInterval(SummaryArtifactCache.retention) }
    let expired = await cache.read(key, lease: newLease)
    precondition(expired == nil)
    try store.write(SummaryArtifactCache.storageKey, data: Data("{broken".utf8))
    let broken = await cache.read(key, lease: newLease)
    precondition(broken == nil)
    await cache.write("recovered", key: key, ownerID: owner, lease: newLease)
    guard case .data(let valid) = store.readOutcome(SummaryArtifactCache.storageKey) else { preconditionFailure() }
    let corrupted = String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "recovered", with: "fabricated")
    try store.write(SummaryArtifactCache.storageKey, data: Data(corrupted.utf8))
    let tampered = await cache.read(key, lease: newLease)
    precondition(tampered == nil)
    guard case .data(let original) = store.readOutcome("existing-record") else { preconditionFailure() }
    precondition(original == Data("unchanged".utf8))
    print("SummaryArtifactCacheChecks: PASS; real SQLite restart, synchronous lease revocation, stale writes, TTL/LRU/entry bounds, owner erasure, corruption/hash refusal and existing data preservation. No network.")
  }
}
