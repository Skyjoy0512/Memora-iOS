import Foundation
import Synchronization

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
  /// The records the last successful commit wrote, so a save only encodes the
  /// rows that changed. Seeded from the archive when the app loads. Touched
  /// only on the persistence queue, which is what keeps a diff honest.
  nonisolated(unsafe) private static var meetingBase: [Meeting]?
  /// Bumped for every enqueued background save, so a save that a newer one has
  /// already superseded is skipped instead of encoding the same array again.
  nonisolated private static let backgroundSaveGenerations = Mutex<[String: Int]>([:])

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
    switch readDocument(key) {
    case .data(let data):
      return .data(data)
    case .failed:
      return .failed
    case .absent:
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
    switch LocalStore.shared.readOutcome(marker) {
    case .data: return readDocument(key)
    case .failed: return .failed
    case .missing: break
    }
    guard let legacy = UserDefaults.standard.data(forKey: key) else { return .absent }

    do {
      // The document and its marker land in one transaction, so a document can
      // never be migrated without also recording that it was. Recheck both
      // under the write lock so a queued or external write wins over legacy.
      if try commitIfCurrent(writes: [(key, legacy), (marker, Data("1".utf8))], removing: [],
                             expecting: [(key, nil), (marker, nil)]) {
        return .data(legacy)
      }
    } catch {
      return .failed
    }
    switch readDocument(key) {
    case .data(let data): return .data(data)
    case .failed: return .failed
    case .absent:
      if case .data = LocalStore.shared.readOutcome(marker) { return readDocument(key) }
      return .failed
    }
  }

  private static func readDocument(_ key: String) -> LoadOutcome {
    switch LocalStore.shared.readOutcome(key) {
    case .data(let data): return .data(data)
    case .missing: return .absent
    case .failed: return .failed
    }
  }

  /// Editors need the last accepted draft even while an unrelated large write
  /// is ahead of it. Ordinary record reads keep their committed-data semantics.
  static func loadLatestData(_ key: String) -> LoadOutcome {
    if let pending = pendingDataWrites[key] { return .data(pending.data) }
    return load(key)
  }

  /// Archives the exact unreadable version and removes it in one transaction.
  @discardableResult
  static func quarantine(_ data: Data, key: String) -> Bool {
    let archive = key + ".unreadable"
    let marker = (key: key + ".migrated", data: Data("1".utf8))
    do {
      if try commitIfCurrent(writes: [(archive, data), marker], removing: [key],
                             expecting: [(key, data), (archive, nil)]) {
        return true
      }
      // A later corruption may occur after a clean restoration. Retain the
      // earlier archive, and recheck the original before moving this version.
      let nextArchive = archive + "." + UUID().uuidString
      return try commitIfCurrent(writes: [(nextArchive, data), marker], removing: [key],
                                 expecting: [(key, data), (nextArchive, nil)])
    } catch {
      return false
    }
  }

  private static func commitIfCurrent(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    expecting expected: [(key: String, data: Data?)],
    meetings: [Meeting]? = nil
  ) throws -> Bool {
    let revisions = dataWriteRevisions(for: writes.map(\.key) + removals)
    let committed = try queue.sync {
      try commitMeetingsLocked(writes: writes, removing: removals, expecting: expected, meetings: meetings)
    }
    if committed { settleDataWrites(revisions) }
    return committed
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
    let generation = beginBackgroundSave(key)
    queue.async {
      // A newer save of the same document supersedes this one, so encoding and
      // writing this snapshot would only repeat work.
      guard isCurrentBackgroundSave(key, generation) else { return }
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

  /// The records, written as rows. Only the records that changed are encoded
  /// and written; the collection is no longer re-encoded as a whole.
  static func saveMeetings(_ meetings: [Meeting], onFailure: (@MainActor () -> Void)? = nil) {
    let key = MemoraModel.StorageKey.meetings
    let generation = beginBackgroundSave(key)
    queue.async {
      guard isCurrentBackgroundSave(key, generation) else { return }
      do {
        try commitMeetingsLocked(writes: [], removing: [], meetings: meetings)
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

  /// The records, saved on the caller's turn and reported before continuing.
  static func saveMeetingsNow(_ meetings: [Meeting]) throws {
    _ = try commitIfCurrent(writes: [], removing: [], expecting: [], meetings: meetings)
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
    _ = try commitIfCurrent(writes: writes, removing: removals, expecting: [])
  }

  /// The same commit, with the record rows that belong to the operation. The
  /// rows, the manifest and the other documents land in one transaction.
  static func commitNow(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    meetings: [Meeting]
  ) throws {
    _ = try commitIfCurrent(writes: writes, removing: removals, expecting: [], meetings: meetings)
  }

  /// The same commit off the caller's turn, so a screen does not wait on disk.
  static func commitAsync(
    writes: [(key: String, data: Data)],
    removing removals: [String]
  ) async throws {
    try await commitAsync(writes: writes, removing: removals, meetings: nil)
  }

  static func commitAsync(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    meetings: [Meeting]?
  ) async throws {
    let revisions = dataWriteRevisions(for: writes.map(\.key) + removals)
    let committedBase: [Meeting]? = try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try Self.commitMeetingsLocked(writes: writes, removing: removals, meetings: meetings)
          continuation.resume(returning: meetings)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    settleDataWrites(revisions)
    if let committedBase { meetingBase = committedBase }
  }

  /// Runs inside the writer queue. Encoding, the transaction and the base
  /// update share one turn, so a queued save can never diff against a state
  /// that a later save already replaced.
  @discardableResult
  nonisolated private static func commitMeetingsLocked(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    expecting expected: [(key: String, data: Data?)] = [],
    meetings: [Meeting]?
  ) throws -> Bool {
    var documents = writes
    var archive: MeetingArchive.Change?
    if let meetings {
      let change = try MeetingArchive.change(from: meetingBase, to: meetings)
      if change.manifestChanged || change.rebuild != nil {
        documents.append((key: MeetingArchive.manifestKey,
                          data: try MeetingArchive.manifestData(change.manifest)))
      }
      archive = change
    }
#if DEBUG
    try consumeInjectedFailure()
#endif
    let landed = try LocalStore.shared.applyBatch(
      writes: documents, removing: removals, expecting: expected, archive: archive)
    if landed, let meetings { meetingBase = meetings }
    return landed
  }

  /// What the archive holds, or nil when the collection document is still the
  /// authority. The records become the base for the next incremental save.
  static func loadMeetings() -> MeetingArchive.Load {
    let outcome = MeetingArchive.load(LocalStore.shared)
    if case .records(let records) = outcome { seedMeetingBase(records) }
    return outcome
  }

  /// The whole collection as stored, for checks that compare what was written
  /// with what the app shows. Prefers the rows; falls back to the document.
  static func storedMeetings() -> [Meeting]? {
    switch loadMeetings() {
    case .records(let records): return records
    case .absent, .invalid:
      guard case .data(let data) = load(MemoraModel.StorageKey.meetings) else { return nil }
      return try? JSONDecoder().decode([Meeting].self, from: data)
    }
  }

  /// Records read by another route become the diff base, so the first save
  /// after a restore does not rewrite every row.
  static func seedMeetingBase(_ meetings: [Meeting]) {
    queue.sync { meetingBase = meetings }
  }

  private static func beginBackgroundSave(_ key: String) -> Int {
    backgroundSaveGenerations.withLock { generations in
      let next = (generations[key] ?? 0) + 1
      generations[key] = next
      return next
    }
  }

  private static func isCurrentBackgroundSave(_ key: String, _ generation: Int) -> Bool {
    backgroundSaveGenerations.withLock { $0[key] == generation }
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
