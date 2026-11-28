import Foundation

/// Stores the record collection as one document per record.
///
/// The records are written here rather than in `RecordStore` so the document
/// store itself stays independent of `Meeting`; a check that only needs the
/// document store does not have to compile the record model. The transaction is
/// still `RecordStore`'s: rows, the manifest and the operation's other
/// documents commit together or not at all.
extension RecordStore {
  /// The records the last successful commit wrote, so a save only encodes the
  /// rows that changed. Seeded from the archive when the app loads. Touched
  /// only on the persistence queue, which is what keeps a diff honest.
  nonisolated(unsafe) private static var meetingBase: [Meeting]?

  /// Saves the records off the caller's turn. Only the documents that changed
  /// are encoded and written.
  static func saveMeetings(
    _ meetings: [Meeting],
    onFailure: (@MainActor () -> Void)? = nil,
    onComplete: (@MainActor () -> Void)? = nil
  ) {
    let key = MemoraModel.StorageKey.meetings
    let generation = beginBackgroundSave(key)
    queue.async {
      // A newer save supersedes this snapshot; encoding it would repeat work.
      guard isCurrentBackgroundSave(key, generation) else { return }
      do {
        try commitMeetingsLocked(writes: [], removing: [], expecting: [], meetings: meetings)
        if let onComplete { Task { @MainActor in onComplete() } }
      } catch {
        Task { @MainActor in onFailure?() }
      }
    }
  }

  /// The records, saved on the caller's turn and reported before continuing.
  static func saveMeetingsNow(_ meetings: [Meeting]) throws {
    _ = try commitMeetingsLocked(writes: [], removing: [], expecting: [], meetings: meetings)
  }

  /// The same commit, with the record rows that belong to the operation. The
  /// rows, the manifest and the other documents land in one transaction.
  static func commitNow(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    meetings: [Meeting],
    prepared: [UUID: Data] = [:]
  ) throws {
    _ = try commitMeetingsLocked(writes: writes, removing: removals, expecting: [],
                                 meetings: meetings, prepared: prepared)
  }

  /// The awaitable form, for a screen that must not wait on disk.
  static func commitAsync(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    meetings: [Meeting]?
  ) async throws {
    let revisions = dataWriteRevisions(for: writes.map(\.key) + removals)
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try commitMeetingsLocked(writes: writes, removing: removals, expecting: [], meetings: meetings)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    settleDataWrites(revisions)
  }

  /// Runs inside the writer queue, so the diff base cannot be replaced between
  /// choosing what to write and writing it.
  nonisolated static func commitMeetingsLocked(
    writes: [(key: String, data: Data)],
    removing removals: [String],
    expecting expected: [(key: String, data: Data?)],
    meetings: [Meeting]?,
    prepared: [UUID: Data] = [:]
  ) throws {
    var documents = writes
    var removals = removals
    var expected = expected
    if let meetings {
      let change: MeetingArchive.Change
      if meetingBase == nil {
        // The archive is not the authority yet (the first save after upgrading,
        // or after a damaged archive). Read the collection the model loaded and
        // require it to be unchanged when the switch commits.
        let source: Data?
        switch LocalStore.shared.readOutcome(MeetingRowStaging.collectionKey) {
        case .data(let data): source = data
        case .missing: source = nil
        case .failed: throw LocalStore.StoreError.open(0)
        }
        change = try MeetingArchive.change(from: nil, to: meetings, collection: source,
                                            prepared: prepared)
        documents.append((key: MeetingArchive.manifestKey,
                          data: try MeetingArchive.manifestData(change.manifest)))
        expected.append((MeetingRowStaging.collectionKey, source))
        if let source {
          documents.append((key: MeetingArchive.legacyKey, data: source))
        }
      } else {
        change = try MeetingArchive.change(from: meetingBase, to: meetings, collection: nil,
                                            prepared: prepared)
        if change.manifestChanged {
          documents.append((key: MeetingArchive.manifestKey,
                            data: try MeetingArchive.manifestData(change.manifest)))
        }
      }
      documents += change.documents
      removals += change.rebuild != nil
        ? MeetingArchive.staleRemovals(for: change, in: LocalStore.shared)
        : change.removals
    }
    let landed = try commitDocumentsLocked(writes: documents, removing: removals, expecting: expected)
    if landed, let meetings { meetingBase = meetings }
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
}
