import CryptoKit
import Foundation

/// The record collection stored one record per document, beside the legacy blob.
///
/// The collection used to be a single document: every edit re-encoded and
/// rewrote every record. At 50,000 records that is 300 MB of JSON for one
/// changed title. Here a save writes the documents that changed and, only when
/// the set or order changed, the small manifest that lists the record ids. The
/// legacy collection is moved aside rather than deleted on the first write, so
/// an older build still has something to read and the switch stays reversible.
///
/// Rows live in the same `documents` table as everything else, which is what
/// keeps a record save and its draft or trash entry in one transaction through
/// the existing `RecordStore` boundary.
struct MeetingArchive {
  /// Prefix of every record row. `keyRange` bounds it for one ordered read.
  static let rowPrefix = "memora.meeting."
  /// The manifest that makes the row set authoritative: the ids in display
  /// order.
  static let manifestKey = "memora.meetings.archive.v1"
  /// Where the previous collection document is kept after the switch.
  static let legacyKey = "memoraMeetings.legacy"

  static let schemaVersion = 1
  private static let digestBytes = 32
  /// Rows decoded together on the launch path.
  private static let batchSize = 512

  static let keyRange = (lower: rowPrefix, upper: "memora.meeting/")

  struct Manifest: Codable, Equatable {
    var schemaVersion = MeetingArchive.schemaVersion
    var ids: [UUID]
  }

  /// One row: the digest of the payload, then the payload itself. The digest
  /// stays with the bytes it covers, so a document table backup or a page read
  /// cannot separate them.
  struct Row {
    var id: UUID
    var document: Data
  }

  /// One commit's worth of work, expressed as the documents the store already
  /// knows how to write.
  struct Change {
    var manifest: Manifest
    var manifestChanged: Bool
    /// Rows to write, and rows to remove. The manifest is in `documents`.
    var documents: [(key: String, data: Data)]
    var removals: [String]
    /// Set when the previous state is unknown: the rows are rebuilt from the
    /// collection document, which must still hold `rebuildSource` when the
    /// commit lands.
    var rebuild: [Meeting]?
    var rebuildSource: Data?
  }

  enum Failure: Error, Equatable {
    case duplicateID
  }

  static func rowKey(_ id: UUID) -> String {
    rowPrefix + id.uuidString.lowercased()
  }

  // MARK: - Reading

  enum Load {
    /// No archive yet: the collection document is still the authority.
    case absent
    case records([Meeting])
    /// The archive exists but could not be served; the caller falls back to the
    /// collection document and rebuilds on the next save.
    case invalid
  }

  static func load(_ store: LocalStore) -> Load {
    let manifestData: Data
    switch store.readOutcome(manifestKey) {
    case .missing: return .absent
    case .failed: return .invalid
    case .data(let data): manifestData = data
    }
    guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
          manifest.schemaVersion == schemaVersion,
          manifest.ids.count <= 100_000 else { return .invalid }

    var records = [Meeting?](repeating: nil, count: manifest.ids.count)
    var positions: [UUID: Int] = [:]
    positions.reserveCapacity(manifest.ids.count)
    for (index, id) in manifest.ids.enumerated() { positions[id] = index }

    // Decoding is the expensive half of a launch read, and each record is
    // independent. A batch of rows is collected and decoded across cores, so
    // only the batch is in memory at once and the whole collection is never
    // held twice. The order is restored from the manifest.
    let workers = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
    var batch: [(position: Int, payload: Data)] = []
    batch.reserveCapacity(batchSize)
    var failed = false

    func flush() {
      guard !batch.isEmpty, !failed else { batch.removeAll(keepingCapacity: true); return }
      let pending = batch
      batch.removeAll(keepingCapacity: true)
      var decoded = [Meeting?](repeating: nil, count: pending.count)
      let slices = min(workers, max(1, pending.count / 64))
      decoded.withUnsafeMutableBufferPointer { buffer in
        let result = buffer
        DispatchQueue.concurrentPerform(iterations: slices) { slice in
          // Each slice owns a disjoint range; nothing here touches the store.
          let local = JSONDecoder()
          let start = pending.count * slice / slices
          let end = pending.count * (slice + 1) / slices
          for index in start..<end {
            result[index] = try? local.decode(Meeting.self, from: pending[index].payload)
          }
        }
      }
      for (index, record) in decoded.enumerated() {
        guard let record, record.id == manifest.ids[pending[index].position] else {
          failed = true
          return
        }
        records[pending[index].position] = record
      }
    }

    var scanned = 0
    do {
      scanned = try store.scanDocuments(inKeyRange: keyRange) { key, document in
        guard !failed, key.count == rowPrefix.count + 36,
              let id = UUID(uuidString: String(key.dropFirst(rowPrefix.count))),
              let position = positions[id], records[position] == nil,
              let payload = verifiedPayload(document, expecting: id) else {
          throw Failure.duplicateID
        }
        batch.append((position, payload))
        if batch.count == batchSize { flush() }
      }
    } catch {
      return .invalid
    }
    flush()
    guard !failed, scanned == manifest.ids.count else { return .invalid }
    let loaded = records.compactMap { $0 }
    guard loaded.count == manifest.ids.count else { return .invalid }
    return .records(loaded)
  }

  /// The digest-checked payload of a row document.
  private static func verifiedPayload(_ document: Data, expecting id: UUID) -> Data? {
    guard document.count > digestBytes else { return nil }
    let digest = document.prefix(digestBytes)
    let payload = document.dropFirst(digestBytes)
    guard Data(SHA256.hash(data: payload)) == digest else { return nil }
    return Data(payload)
  }

  private static func decode(_ document: Data, expecting id: UUID, decoder: JSONDecoder) -> Meeting? {
    guard document.count > digestBytes else { return nil }
    let digest = document.prefix(digestBytes)
    let payload = document.dropFirst(digestBytes)
    guard Data(SHA256.hash(data: payload)) == digest,
          let record = try? decoder.decode(Meeting.self, from: payload),
          record.id == id else { return nil }
    return record
  }

  // MARK: - Writing

  /// The work needed to store `meetings` after `previous`. `previous` is what
  /// the last successful commit wrote; nil means it is not known, so the rows
  /// are rebuilt from the collection document.
  /// `prepared` carries payloads the caller already encoded (off the main
  /// actor, say), so the save does not encode them a second time.
  static func change(
    from previous: [Meeting]?,
    to meetings: [Meeting],
    collection: Data?,
    prepared: [UUID: Data] = [:]
  ) throws -> Change {
    guard let previous else {
      let rows = try rebuiltRows(meetings, legacy: collection)
      return Change(manifest: Manifest(ids: meetings.map(\.id)), manifestChanged: true,
                    documents: rows.map { (rowKey($0.id), $0.document) },
                    removals: [MeetingRowStaging.collectionKey],
                    rebuild: meetings, rebuildSource: collection)
    }
    let encoder = JSONEncoder()
    // The common case: the same records in the same order. Nothing but the
    // changed rows is encoded and the id list is not rebuilt at all.
    if previous.count == meetings.count,
       previous.elementsEqual(meetings, by: { $0.id == $1.id }) {
      var documents: [(key: String, data: Data)] = []
      for (record, stored) in zip(meetings, previous) where record != stored {
        documents.append((rowKey(record.id), try row(record, encoding: prepared[record.id],
                                                      encoder: encoder)))
      }
      return Change(manifest: Manifest(ids: []), manifestChanged: false, documents: documents,
                    removals: [], rebuild: nil, rebuildSource: nil)
    }

    let manifest = Manifest(ids: meetings.map(\.id))
    var positions: [UUID: Int] = [:]
    positions.reserveCapacity(previous.count)
    for (index, record) in previous.enumerated() { positions[record.id] = index }

    var documents: [(key: String, data: Data)] = []
    var removed: [String] = []
    var kept = Set<UUID>()
    kept.reserveCapacity(meetings.count)
    for record in meetings {
      guard kept.insert(record.id).inserted else { throw Failure.duplicateID }
      guard let position = positions[record.id] else {
        documents.append((rowKey(record.id), try row(record, encoding: prepared[record.id],
                                                      encoder: encoder)))
        continue
      }
      if previous[position] != record {
        documents.append((rowKey(record.id), try row(record, encoding: prepared[record.id],
                                                      encoder: encoder)))
      }
    }
    if meetings.count != previous.count {
      let present = kept
      removed = previous.map(\.id).filter { !present.contains($0) }.map(rowKey)
    }
    let orderChanged = manifest.ids != previous.map(\.id)
    return Change(manifest: manifest, manifestChanged: orderChanged, documents: documents,
                  removals: removed, rebuild: nil, rebuildSource: nil)
  }

  /// Row keys that exist in the store but are not in `change`, so a rebuild
  /// leaves nothing behind.
  static func staleRemovals(for change: Change, in store: LocalStore) -> [String] {
    guard change.rebuild != nil else { return change.removals }
    let written = Set(change.documents.map(\.key))
    var stale: [String] = []
    _ = try? store.scanDocuments(inKeyRange: keyRange) { key, _ in
      if !written.contains(key) { stale.append(key) }
    }
    return stale + change.removals
  }

  /// Rows for an unknown base. The collection document is split at its own
  /// object boundaries so a record the person did not touch keeps its original
  /// bytes, including fields this build does not know about.
  static func rebuiltRows(_ meetings: [Meeting], legacy: Data?) throws -> [Row] {
    if let legacy, let slices = try? MeetingRowStaging.objectRanges(in: legacy),
       slices.count == meetings.count {
      let decoder = JSONDecoder()
      var rows: [Row] = []
      rows.reserveCapacity(slices.count)
      for (index, range) in slices.enumerated() {
        let payload = legacy.subdata(in: range)
        guard let record = try? decoder.decode(Meeting.self, from: payload),
              record.id == meetings[index].id else { return try encodedRows(meetings) }
        rows.append(Row(id: record.id, document: document(payload, digest: Data(SHA256.hash(data: payload)))))
      }
      return rows
    }
    return try encodedRows(meetings)
  }

  private static func encodedRows(_ meetings: [Meeting]) throws -> [Row] {
    let encoder = JSONEncoder()
    return try meetings.map { record in
      let payload = try encoder.encode(record)
      return Row(id: record.id,
                 document: document(payload, digest: Data(SHA256.hash(data: payload))))
    }
  }

  private static func row(_ record: Meeting, encoding payload: Data?,
                          encoder: JSONEncoder) throws -> Data {
    let payload = try payload ?? encoder.encode(record)
    return document(payload, digest: Data(SHA256.hash(data: payload)))
  }

  private static func document(_ payload: Data, digest: Data) -> Data {
    var document = Data(capacity: digest.count + payload.count)
    document.append(digest)
    document.append(payload)
    return document
  }

  static func manifestData(_ manifest: Manifest) throws -> Data {
    try JSONEncoder().encode(manifest)
  }
}
