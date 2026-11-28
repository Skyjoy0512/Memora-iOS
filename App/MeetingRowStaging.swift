import CryptoKit
import Foundation

/// Stages each record as its own document, next to the legacy collection.
///
/// The collection stays the authority until a verified checkpoint exists; the
/// sealed reader then serves pages without trusting the live store. Keeping this
/// in the app lets the migration run against the real store rather than only in
/// the rehearsal checks.
struct MeetingRowStaging {
  static let collectionKey = "memoraMeetings"
  static let checkpointKey = "fixture.meeting-rows.checkpoint"
  static let pageSize = 64
  private static let maximumPageBytes = 8 * 1_024 * 1_024
  private static let digestBytes = 32

  struct Checkpoint: Codable, Equatable {
    var schemaVersion = 1
    var generation = UUID()
    var sourceFingerprint: String
    var count: Int
    var stagedCount = 0
    var verified = false
    var pageDigests: [Data]?

    var pageCount: Int { (count + MeetingRowStaging.pageSize - 1) / MeetingRowStaging.pageSize }

    func rowKey(_ ordinal: Int) -> String {
      "fixture.meeting-rows.\(generation.uuidString).\(ordinal)"
    }

    func pageKey(_ index: Int) -> String {
      "fixture.meeting-rows.\(generation.uuidString).page.\(index)"
    }

    fileprivate var stagedKeys: [String] {
      (0..<stagedCount).map(rowKey) + (pageDigests?.indices.map(pageKey) ?? [])
    }
  }

  enum Failure: Error, Equatable {
    case unavailable
    case missingSource
    case malformedCollection
    case invalidCheckpoint
    case conflict
    case outOfRange
    case unfinished
    case invalidRow(Int)
    case invalidPage(Int)
    case pageTooLarge
    case duplicateRecordID
    case missingMedia(Int)
  }

  /// Reads a sealed offline snapshot using a trusted checkpoint from verify.
  /// This reader has no live authority. Its SQLite change token represents the
  /// opened fixture, and it refuses to serve pages after the fixture changes.
  struct SealedReader {
    struct Page {
      var offset: Int
      var records: [Meeting]
      var payloadBytes: Int
    }

    private let store: LocalStore
    private let checkpoint: Checkpoint
    private let pageDigests: [Data]
    private let changeToken: String

    init(store: LocalStore, verified checkpoint: Checkpoint) throws {
      guard let token = store.changeToken else { throw Failure.unavailable }
      let (_, stored) = try savedCheckpoint(in: store)
      guard checkpoint == stored else { throw Failure.conflict }
      guard checkpoint.verified, let digests = checkpoint.pageDigests else { throw Failure.unfinished }
      guard token == store.changeToken else { throw Failure.conflict }
      self.store = store
      self.checkpoint = checkpoint
      pageDigests = digests
      changeToken = token
    }

    var count: Int { checkpoint.count }
    var pageCount: Int { checkpoint.pageCount }

    func page(_ index: Int, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws -> Page {
      guard pageDigests.indices.contains(index) else { throw Failure.outOfRange }
      try checkCancellation()
      guard store.changeToken == changeToken else { throw Failure.conflict }
      let start = index * pageSize
      let end = min(start + pageSize, count)
      guard let digests = try read(store, key: checkpoint.pageKey(index)),
            digests.count == (end - start) * digestBytes,
            Data(SHA256.hash(data: digests)) == pageDigests[index] else { throw Failure.invalidPage(index) }
      let decoder = JSONDecoder()
      var page = Page(offset: start, records: [], payloadBytes: 0)
      page.records.reserveCapacity(end - start)
      for ordinal in start..<end {
        try checkCancellation()
        let offset = (ordinal - start) * digestBytes
        guard let bytes = try read(store, key: checkpoint.rowKey(ordinal)) else { throw Failure.invalidRow(ordinal) }
        guard bytes.count <= maximumPageBytes - page.payloadBytes else { throw Failure.pageTooLarge }
        guard Data(SHA256.hash(data: bytes)) == digests[offset..<(offset + digestBytes)],
              let record = try? decoder.decode(Meeting.self, from: bytes) else { throw Failure.invalidRow(ordinal) }
        page.records.append(record)
        page.payloadBytes += bytes.count
      }
      try checkCancellation()
      guard store.changeToken == changeToken else { throw Failure.conflict }
      return page
    }
  }

  private let store: LocalStore
  private let source: Data
  private let ranges: [Range<Int>]
  private let fingerprint: String

  init(store: LocalStore) throws {
    self.store = store
    guard let data = try Self.read(store, key: Self.collectionKey) else { throw Failure.missingSource }
    source = data
    ranges = try Self.objectRanges(in: data)
    fingerprint = Data(SHA256.hash(data: data)).base64EncodedString()
  }

  func stage(maximumRows: Int, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws -> Checkpoint {
    guard (1...4_096).contains(maximumRows) else { throw Failure.outOfRange }
    try checkCancellation()
    let (previousBytes, previous) = try Self.savedCheckpoint(in: store)
    var checkpoint = Checkpoint(sourceFingerprint: fingerprint, count: ranges.count)
    var removals: [String] = []
    if let previous {
      if previous.sourceFingerprint == fingerprint {
        guard previous.count == ranges.count else { throw Failure.invalidCheckpoint }
        checkpoint = previous
      } else {
        removals = previous.stagedKeys
      }
    }
    let limit = min(checkpoint.stagedCount + maximumRows, ranges.count)
    var end = checkpoint.stagedCount
    var byteCount = 0
    var writes: [(key: String, data: Data)] = []
    let decoder = JSONDecoder()
    while end < limit {
      try checkCancellation()
      let range = ranges[end]
      if !writes.isEmpty, range.count > 8 * 1_024 * 1_024 - byteCount { break }
      let row = source.subdata(in: range)
      guard (try? decoder.decode(Meeting.self, from: row)) != nil else { throw Failure.invalidRow(end) }
      writes.append((checkpoint.rowKey(end), row))
      byteCount += range.count
      end += 1
    }
    if previous != checkpoint || checkpoint.stagedCount != end {
      checkpoint.stagedCount = end
      writes.append((Self.checkpointKey, try JSONEncoder().encode(checkpoint)))
    }
    try checkCancellation()
    try apply(writes: writes, removing: removals, previousCheckpoint: previousBytes)
    return checkpoint
  }

  /// Verifies exact row bytes and record identities while visiting rows one at
  /// a time. The closing transaction rechecks the original, the checkpoint
  /// and every row; Data slices retain the source buffer during that check.
  func verify(mediaExists: (Meeting) -> Bool,
              checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws -> Checkpoint {
    let (bytes, loaded) = try Self.savedCheckpoint(in: store)
    guard var checkpoint = loaded, checkpoint.sourceFingerprint == fingerprint,
          checkpoint.count == ranges.count, checkpoint.stagedCount == ranges.count else { throw Failure.unfinished }
    let decoder = JSONDecoder()
    var ids: Set<UUID> = []
    var expectedRows: [(key: String, data: Data?)] = []
    expectedRows.reserveCapacity(ranges.count + checkpoint.pageCount)
    var writes: [(key: String, data: Data)] = []
    var pageDigests: [Data] = []
    var rowDigests = Data()
    for ordinal in ranges.indices {
      try checkCancellation()
      let key = checkpoint.rowKey(ordinal)
      let expected = source[ranges[ordinal]]
      let row = try Self.read(store, key: key)
      guard let row, row == expected,
            let meeting = try? decoder.decode(Meeting.self, from: row) else { throw Failure.invalidRow(ordinal) }
      guard ids.insert(meeting.id).inserted else { throw Failure.duplicateRecordID }
      guard mediaExists(meeting) else { throw Failure.missingMedia(ordinal) }
      expectedRows.append((key, expected))
      rowDigests.append(contentsOf: SHA256.hash(data: expected))
      if (ordinal + 1) % Self.pageSize == 0 || ordinal + 1 == ranges.count {
        let pageKey = checkpoint.pageKey(pageDigests.count)
        pageDigests.append(Data(SHA256.hash(data: rowDigests)))
        if checkpoint.pageDigests == nil {
          writes.append((pageKey, rowDigests))
        } else {
          expectedRows.append((pageKey, rowDigests))
        }
        rowDigests = Data()
      }
    }
    if let saved = checkpoint.pageDigests {
      guard saved == pageDigests else { throw Failure.invalidCheckpoint }
    } else {
      checkpoint.verified = true
      checkpoint.pageDigests = pageDigests
      writes.append((Self.checkpointKey, try JSONEncoder().encode(checkpoint)))
    }
    try checkCancellation()
    try apply(writes: writes, removing: [], previousCheckpoint: bytes, expectingRows: expectedRows)
    return checkpoint
  }

  func discard() throws {
    let (bytes, checkpoint) = try Self.savedCheckpoint(in: store)
    guard let checkpoint else { return }
    try apply(writes: [], removing: checkpoint.stagedKeys + [Self.checkpointKey], previousCheckpoint: bytes)
  }

  private static func savedCheckpoint(in store: LocalStore) throws -> (Data?, Checkpoint?) {
    guard let data = try Self.read(store, key: Self.checkpointKey) else { return (nil, nil) }
    guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
          checkpoint.schemaVersion == 1, (0...100_000).contains(checkpoint.count),
          (0...checkpoint.count).contains(checkpoint.stagedCount),
          !checkpoint.verified || checkpoint.count == checkpoint.stagedCount else { throw Failure.invalidCheckpoint }
    if let pageDigests = checkpoint.pageDigests {
      guard checkpoint.verified, pageDigests.count == checkpoint.pageCount,
            pageDigests.allSatisfy({ $0.count == digestBytes }) else { throw Failure.invalidCheckpoint }
    }
    return (data, checkpoint)
  }

  private func apply(writes: [(key: String, data: Data)], removing: [String], previousCheckpoint: Data?,
                     expectingRows: [(key: String, data: Data?)] = []) throws {
    guard try store.applyBatch(writes: writes, removing: removing,
      expecting: [(Self.collectionKey, source), (Self.checkpointKey, previousCheckpoint)] + expectingRows) else {
      throw Failure.conflict
    }
  }

  private static func read(_ store: LocalStore, key: String) throws -> Data? {
    switch store.readOutcome(key) {
    case .data(let data): data
    case .missing: nil
    case .failed: throw Failure.unavailable
    }
  }

  /// Indexes top-level object boundaries. The Meeting decoder checks each
  /// object; staging keeps the original bytes, including fields it ignores.
  /// The row archive reuses this so its migration also keeps untouched bytes.
  static func objectRanges(in source: Data) throws -> [Range<Int>] {
    try source.withUnsafeBytes { bytes in
      var cursor = 0
      var ranges: [Range<Int>] = []
      func space() {
        while cursor < bytes.count && [UInt8(0x20), 0x09, 0x0A, 0x0D].contains(bytes[cursor]) { cursor += 1 }
      }
      func take(_ byte: UInt8) -> Bool {
        guard cursor < bytes.count, bytes[cursor] == byte else { return false }
        cursor += 1
        return true
      }
      space()
      guard take(0x5B) else { throw Failure.malformedCollection }
      space()
      if !take(0x5D) {
        while true {
          let start = cursor
          guard take(0x7B), ranges.count < 100_000 else { throw Failure.malformedCollection }
          var closing: [UInt8] = [0x7D]
          var quoted = false
          var escaped = false
          while !closing.isEmpty {
            guard cursor < bytes.count, closing.count <= 512 else { throw Failure.malformedCollection }
            let byte = bytes[cursor]
            cursor += 1
            if quoted {
              if escaped { escaped = false }
              else if byte == 0x5C { escaped = true }
              else if byte == 0x22 { quoted = false }
            } else {
              switch byte {
              case 0x22: quoted = true
              case 0x7B: closing.append(0x7D)
              case 0x5B: closing.append(0x5D)
              case 0x7D, 0x5D:
                guard closing.removeLast() == byte else { throw Failure.malformedCollection }
              default: break
              }
            }
          }
          ranges.append(start..<cursor)
          space()
          if take(0x5D) { break }
          guard take(0x2C) else { throw Failure.malformedCollection }
          space()
        }
      }
      space()
      guard cursor == bytes.count else { throw Failure.malformedCollection }
      return ranges
    }
  }
}
