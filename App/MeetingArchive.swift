import CryptoKit
import Foundation

/// The record collection stored one record per row, beside the legacy blob.
///
/// The collection used to be a single document: every edit re-encoded and
/// rewrote every record. At 50,000 records that is 300 MB of JSON for one
/// changed title. Here a save writes the rows that changed and, only when the
/// set or order changed, the small manifest that lists the record ids. The
/// legacy collection is moved aside rather than deleted on the first write, so
/// an older build still has something to read and the switch stays reversible.
struct MeetingArchive {
  /// The manifest that makes the row set authoritative: the ids in display
  /// order plus a revision for diagnostics. Stored in the same `documents`
  /// table, so it commits in the same SQLite transaction as the rows.
  static let manifestKey = "memora.meetings.archive.v1"
  /// Where the previous collection document is kept after the switch.
  static let legacyKey = "memoraMeetings.legacy"

  static let schemaVersion = 1

  struct Manifest: Codable, Equatable {
    var schemaVersion = MeetingArchive.schemaVersion
    var ids: [UUID]
  }

  struct Row {
    var id: UUID
    var digest: Data
    var payload: Data
  }

  /// One commit's worth of row work. `rebuild` is set when the previous state
  /// is unknown (first save after launch, or a suspected damaged archive): the
  /// rows are then produced inside the write transaction from the collection
  /// document, so the bytes that are already on disk are kept where possible.
  struct Change {
    var manifest: Manifest
    /// False when the stored order is unchanged, so an edit writes only its own
    /// row and does not re-encode the list of ids.
    var manifestChanged: Bool
    var clearsRows: Bool
    var rows: [Row]
    var removals: [UUID]
    var rebuild: [Meeting]?
  }

  enum Failure: Error, Equatable {
    case duplicateID
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
          manifest.ids.count <= 100_000,
          Set(manifest.ids).count == manifest.ids.count else { return .invalid }

    let decoder = JSONDecoder()
    var records = [Meeting?](repeating: nil, count: manifest.ids.count)
    var positions: [UUID: Int] = [:]
    positions.reserveCapacity(manifest.ids.count)
    for (index, id) in manifest.ids.enumerated() { positions[id] = index }

    var scanned = 0
    do {
      scanned = try store.scanMeetingRows { id, digest, payload in
        guard let position = positions[id], records[position] == nil,
              Data(SHA256.hash(data: payload)) == digest,
              let record = try? decoder.decode(Meeting.self, from: payload),
              record.id == id else { throw Failure.duplicateID }
        records[position] = record
      }
    } catch {
      return .invalid
    }
    guard scanned == manifest.ids.count else { return .invalid }
    let decoded = records.compactMap { $0 }
    guard decoded.count == manifest.ids.count else { return .invalid }
    return .records(decoded)
  }

  // MARK: - Writing

  /// The work needed to store `meetings` after `previous`. `previous` is what
  /// the last successful commit wrote; nil means it is not known, so the rows
  /// are rebuilt from the collection document in the same transaction.
  static func change(
    from previous: [Meeting]?,
    to meetings: [Meeting]
  ) throws -> Change {
    guard let previous else {
      let manifest = Manifest(ids: meetings.map(\.id))
      return Change(manifest: manifest, manifestChanged: true, clearsRows: true,
                    rows: [], removals: [], rebuild: meetings)
    }
    let encoder = JSONEncoder()
    // The common case: the same records in the same order. Nothing but the
    // changed rows is encoded and the id list is not rebuilt at all.
    if previous.count == meetings.count,
       previous.elementsEqual(meetings, by: { $0.id == $1.id }) {
      var rows: [Row] = []
      for (record, stored) in zip(meetings, previous) where record != stored {
        rows.append(try row(record, encoder: encoder))
      }
      return Change(manifest: Manifest(ids: []), manifestChanged: false, clearsRows: false,
                    rows: rows, removals: [], rebuild: nil)
    }

    let manifest = Manifest(ids: meetings.map(\.id))
    var positions: [UUID: Int] = [:]
    positions.reserveCapacity(previous.count)
    for (index, record) in previous.enumerated() { positions[record.id] = index }

    var rows: [Row] = []
    rows.reserveCapacity(4)
    var removed: [UUID] = []
    var kept = Set<UUID>()
    kept.reserveCapacity(meetings.count)
    for record in meetings {
      guard kept.insert(record.id).inserted else { throw Failure.duplicateID }
      guard let position = positions[record.id] else {
        rows.append(try row(record, encoder: encoder))
        continue
      }
      if previous[position] != record {
        rows.append(try row(record, encoder: encoder))
      }
    }
    if meetings.count != previous.count {
      let present = kept
      removed = previous.map(\.id).filter { !present.contains($0) }
    }
    let orderChanged = manifest.ids != previous.map(\.id)
    return Change(manifest: manifest, manifestChanged: orderChanged, clearsRows: false,
                  rows: rows, removals: removed, rebuild: nil)
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
        rows.append(Row(id: record.id, digest: Data(SHA256.hash(data: payload)), payload: payload))
      }
      return rows
    }
    return try encodedRows(meetings)
  }

  private static func encodedRows(_ meetings: [Meeting]) throws -> [Row] {
    let encoder = JSONEncoder()
    return try meetings.map { record in
      let payload = try encoder.encode(record)
      return Row(id: record.id, digest: Data(SHA256.hash(data: payload)), payload: payload)
    }
  }

  private static func row(_ record: Meeting, encoder: JSONEncoder) throws -> Row {
    let payload = try encoder.encode(record)
    return Row(id: record.id, digest: Data(SHA256.hash(data: payload)), payload: payload)
  }

  static func manifestData(_ manifest: Manifest) throws -> Data {
    try JSONEncoder().encode(manifest)
  }
}
