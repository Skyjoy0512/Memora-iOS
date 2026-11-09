import Foundation
#if DEBUG
import Synchronization
#endif

/// Reads and writes the app's documents. Keeping this here means the model asks
/// for records and never deals with the store, encoding, or the move off
/// `UserDefaults` itself.
///
/// Every write goes through one serial queue, and the writes that must be
/// ordered (a save that has to land before a delete, say) wait for their turn.
/// That is what stops an older queued save from arriving after a newer delete.
@MainActor
enum RecordStore {
  private static let queue = DispatchQueue(label: "app.memora.persistence", qos: .utility)
  private static var pendingDataWrites: [String: PendingDataWrite] = [:]

  private struct PendingDataWrite: Sendable {
    var id = UUID()
    var data: Data
  }

  /// What a load found. Absent and unreadable are different answers: absent may
  /// be a first run, while unreadable must never be treated as one.
  enum LoadOutcome {
    case absent
    case data(Data)
    case failed
  }

  /// Opens the store. Safe to call more than once.
  static func prepare() {
    try? LocalStore.shared.prepare()
  }

#if DEBUG
  /// Lets a debug check make the next write fail, so the error paths are
  /// exercised rather than assumed. Never set in a shipped build.
  nonisolated private static let failureInjection = Mutex(false)

  static func setFailureInjection(_ enabled: Bool) {
    failureInjection.withLock { $0 = enabled }
  }

  nonisolated private static func consumeInjectedFailure() throws {
    // Synchronous and async commits consume the same one-shot flag safely.
    try failureInjection.withLock { failsNextWrite in
      guard failsNextWrite else { return }
      failsNextWrite = false
      throw LocalStore.StoreError.statement(1)
    }
  }
#endif

  /// Waits for any queued writes to land. A read after this sees everything
  /// that has been saved, so a reload cannot pick up stale bytes.
  static func flushAsync() async {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume() }
    }
  }

  /// Reads a document. A missing document may be migrated from the legacy
  /// `UserDefaults` copy exactly once; a read failure is reported as such and
  /// never falls back to older data.
  static func load(_ key: String) -> LoadOutcome {
    switch LocalStore.shared.readOutcome(key) {
    case .data(let data):
      return .data(data)
    case .failed:
      return .failed
    case .missing:
      break
    }

    // Migrated once, and never again: a marker records that this key has already
    // been brought across, so an emptied document cannot resurrect the old copy.
    //
    // The marker is read from the same store the document is written to. It used
    // to live in `UserDefaults`, which nothing removed the old copy from, so a
    // document that was migrated and then deleted was brought in again from the
    // legacy copy on the next launch.
    let marker = key + ".migrated"
    if case .data = LocalStore.shared.readOutcome(marker) { return .absent }
    guard let legacy = UserDefaults.standard.data(forKey: key) else { return .absent }

    do {
      // The document and its marker land in one transaction, so a document can
      // never be migrated without also recording that it was. On failure the old
      // copy is still in `UserDefaults` and no marker was written, so the next
      // load tries again.
      try saveBatch([
        (key: key, data: legacy),
        (key: marker, data: Data("1".utf8)),
      ])
    } catch {
      return .failed
    }
    return .data(legacy)
  }

  /// Editors need the last accepted draft even while an unrelated large write
  /// is ahead of it. Ordinary record reads keep their committed-data semantics.
  static func loadLatestData(_ key: String) -> LoadOutcome {
    if let pending = pendingDataWrites[key] { return .data(pending.data) }
    return load(key)
  }

  /// Keeps an unreadable document aside. The original is only removed once the
  /// copy is safely stored, so a failed quarantine never loses anything.
  @discardableResult
  static func quarantine(_ data: Data, key: String) -> Bool {
    do {
      try LocalStore.shared.write(key + ".unreadable", data: data)
    } catch {
      return false
    }
    do {
      try LocalStore.shared.remove(key)
      return true
    } catch {
      return false
    }
  }

  /// Encodes a value, reporting failure instead of silently dropping it.
  nonisolated static func encoded<T: Encodable>(_ value: T) throws -> Data {
    try JSONEncoder().encode(value)
  }

  /// Saves off the main thread. `onFailure` runs on the main actor when the
  /// document could not be written, including an encoding failure.
  static func save<T: Encodable & Sendable>(
    _ value: T,
    key: String,
    onFailure: (@MainActor () -> Void)? = nil
  ) {
    queue.async {
      guard let data = try? JSONEncoder().encode(value) else {
        Task { @MainActor in onFailure?() }
        return
      }
      do {
        try LocalStore.shared.write(key, data: data)
      } catch {
        Task { @MainActor in onFailure?() }
      }
    }
  }

  /// Completion acknowledges the snapshot that actually reached disk. A log
  /// can retain its dirty revision on failure without delaying business saves.
  static func saveReportingResult<T: Encodable & Sendable>(
    _ value: T,
    key: String,
    completion: @escaping @MainActor (Bool) -> Void
  ) {
    queue.async {
      let succeeded: Bool
      do {
        let data = try JSONEncoder().encode(value)
        try LocalStore.shared.write(key, data: data)
        succeeded = true
      } catch {
        succeeded = false
      }
      Task { @MainActor in completion(succeeded) }
    }
  }

  /// Saves already-encoded bytes off the main thread. For a document whose
  /// format is not JSON — a draft's plain text, say — so that its reader and
  /// writer agree on the bytes rather than on an encoding neither named.
  static func saveData(
    _ data: Data,
    key: String,
    onFailure: (@MainActor () -> Void)? = nil
  ) {
    let pending = PendingDataWrite(data: data)
    pendingDataWrites[key] = pending
    queue.async {
      let succeeded: Bool
      do {
        try LocalStore.shared.write(key, data: data)
        succeeded = true
      } catch {
        succeeded = false
      }
      Task { @MainActor in
        guard pendingDataWrites[key]?.id == pending.id else { return }
        if succeeded {
          pendingDataWrites.removeValue(forKey: key)
        } else {
          // Keep unsaved input available in this process and report that it is
          // not durable. A later save or explicit discard can settle it.
          onFailure?()
        }
      }
    }
  }

  /// Saves on the caller's turn in the queue, throwing when it could not be
  /// written, for the places that must know before continuing. Waits for any
  /// earlier queued write, so ordering is preserved across both kinds of save.
  static func saveNow<T: Encodable>(_ value: T, key: String) throws {
    let data = try JSONEncoder().encode(value)
    try saveBatch([(key: key, data: data)])
  }

  /// Saves already-encoded bytes on the caller's turn, throwing on failure, and
  /// waiting for earlier queued writes. The awaitable form of `saveData`.
  static func saveDataNow(_ data: Data, key: String) throws {
    try saveBatch([(key: key, data: data)])
  }

  /// Writes several documents in one transaction, so a logical operation that
  /// spans documents either lands completely or not at all.
  static func saveBatch(_ documents: [(key: String, data: Data)]) throws {
    try commitNow(writes: documents, removing: [])
  }

  /// Writes and removes documents in one transaction on the caller's turn,
  /// waiting for earlier queued writes. This is what lets a commit store a
  /// record and discard its draft together.
  static func commitNow(
    writes: [(key: String, data: Data)],
    removing removals: [String]
  ) throws {
    let revisions = dataWriteRevisions(for: writes.map(\.key) + removals)
    try queue.sync {
#if DEBUG
      try consumeInjectedFailure()
#endif
      try LocalStore.shared.applyBatch(writes: writes, removing: removals)
    }
    settleDataWrites(revisions)
  }

  /// The same commit off the caller's turn, so a screen does not wait on disk.
  static func commitAsync(
    writes: [(key: String, data: Data)],
    removing removals: [String]
  ) async throws {
    let revisions = dataWriteRevisions(for: writes.map(\.key) + removals)
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
#if DEBUG
          try consumeInjectedFailure()
#endif
          try LocalStore.shared.applyBatch(writes: writes, removing: removals)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    settleDataWrites(revisions)
  }

  /// Removes a document, waiting for any queued write so an older save cannot
  /// land after the removal.
  static func remove(_ key: String) throws {
    try commitNow(writes: [], removing: [key])
  }

  /// Compare after earlier queued writes, in the same turn as the removal.
  /// Otherwise an older commit can erase a newer editor's debounced draft.
  static func remove(_ key: String, ifMatching matches: @Sendable (Data) -> Bool) throws {
    let pending = pendingDataWrites[key]
    let removed = try queue.sync {
      let data: Data
      if let pending { data = pending.data }
      else if case .data(let stored) = LocalStore.shared.readOutcome(key) { data = stored }
      else { return false }
      guard matches(data) else { return false }
#if DEBUG
      try consumeInjectedFailure()
#endif
      try LocalStore.shared.applyBatch(writes: [], removing: [key])
      return true
    }
    if removed { pendingDataWrites.removeValue(forKey: key) }
  }

  private static func dataWriteRevisions(for keys: [String]) -> [String: UUID] {
    Dictionary(uniqueKeysWithValues: Set(keys).compactMap { key in
      pendingDataWrites[key].map { (key, $0.id) }
    })
  }

  private static func settleDataWrites(_ revisions: [String: UUID]) {
    for (key, id) in revisions where pendingDataWrites[key]?.id == id {
      pendingDataWrites.removeValue(forKey: key)
    }
  }
}
