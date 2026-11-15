import Foundation

enum SourceMediaChunkRevisionChecks {
  static func run(root: URL) throws {
    let directory = root.appendingPathComponent("settled-revisions")
    let store = SourceMediaCheckpointStore(directory: directory)
    let key = try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "a", count: 64), suffix: "wav",
      locale: Locale(identifier: "ja-JP"), vocabulary: ["Memora"], pipeline: "recording-speech-analyzer-v1")
    let session = store.begin()
    // Both sides of a chunk boundary may have the same absolute timestamp.
    // Only the completion-time array ranges distinguish their ownership.
    let first = TranscriptSegment(id: UUID(), speaker: "田中", speakerIsCertain: true, timestamp: 900,
      text: "前半の末尾", endTime: 900.5, speakerID: "speaker-a", recognitionEngine: "apple",
      recognitionModel: "SpeechAnalyzer", recognitionLanguage: "ja-JP", recognitionConfidence: 0.5)
    let second = TranscriptSegment(id: UUID(), speaker: "佐藤", speakerIsCertain: false, timestamp: 900,
      text: "後半の冒頭", endTime: 901, speakerID: "speaker-b")
    var prefix = SourceMediaCheckpoint(duration: 1_801, completedChunks: 1, blocks: [], segments: [first])
    prefix.recordSettledChunk(index: 0, segmentRange: 0..<1, key: key)
    let old = prefix.chunkRevisions!.first!
    store.save(prefix, key: key, session: session)
    precondition(store.isCurrent(old, key: key, duration: 1_801, session: session))
    var complete = SourceMediaCheckpoint(duration: 1_801, completedChunks: 2, blocks: [],
      segments: [first, second], chunkRevisions: prefix.chunkRevisions)
    complete.recordSettledChunk(index: 1, segmentRange: 1..<2, key: key)
    let next = complete.chunkRevisions!.last!
    precondition(old.id != next.id && old.contentFingerprint != next.contentFingerprint)
    store.save(complete, key: key, session: session)
    precondition(store.isCurrent(old, key: key, duration: 1_801, session: session), "Append invalidated unchanged evidence")
    let restarted = SourceMediaCheckpointStore(directory: directory)
    let loaded = restarted.load(key, duration: 1_801, session: restarted.begin())!
    precondition(loaded.segments == [first, second] && loaded.chunkRevisions == [old, next])
    precondition(restarted.isCurrent(next, key: key, duration: 1_801, session: restarted.begin()))
    precondition(!store.isCurrent(old, key: key, duration: 1_802, session: session))

    let changes: [(String, (inout TranscriptSegment) -> Void)] = [
      ("text", { $0.text += "を訂正" }), ("segment ID", { $0.id = UUID() }),
      ("speaker", { $0.speaker = "鈴木" }), ("speaker ID", { $0.speakerID = "speaker-c" }),
      ("certainty", { $0.speakerIsCertain = false }), ("identification", { $0.identificationStatus = .unassigned }),
      ("timestamp", { $0.timestamp = 899.9 }), ("end", { $0.endTime = 900.4 }),
      ("engine", { $0.recognitionEngine = "other" }), ("model", { $0.recognitionModel = "revised" }),
      ("language", { $0.recognitionLanguage = "en-US" }), ("confidence", { $0.recognitionConfidence = 0.9 })
    ]
    for (label, change) in changes {
      var edited = complete
      change(&edited.segments![0])
      store.save(edited, key: key, session: session)
      precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session), "Stale \(label) retained")
      precondition(store.isCurrent(next, key: key, duration: 1_801, session: session), "Unchanged suffix lost")
      precondition(store.load(key, duration: 1_801, session: session)?.segments == edited.segments)
      edited.recordSettledChunk(index: 0, segmentRange: 0..<1, key: key)
      let updated = edited.chunkRevisions!.first!
      precondition(updated.id == old.id && updated.contentFingerprint != old.contentFingerprint)
      store.save(edited, key: key, session: session)
      precondition(store.isCurrent(updated, key: key, duration: 1_801, session: session))
      precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session))
    }

    let mutations: [(String, (inout SourceMediaChunkRevision) -> Void)] = [
      ("negative offset", { $0.segmentOffset = -1 }), ("offset overflow", { $0.segmentOffset = .max }),
      ("count overflow", { $0.segmentCount = .max }), ("negative count", { $0.segmentCount = -1 }),
      ("block offset", { $0.blockOffset = .max }), ("block count", { $0.blockCount = .max }),
      ("future chunk", { $0.chunkIndex = .max }), ("negative chunk", { $0.chunkIndex = -1 }),
      ("version", { $0.schemaVersion = 99 }), ("ID", { $0.id = String(repeating: "b", count: 64) }),
      ("source", { $0.sourceBinding = String(repeating: "b", count: 64) }),
      ("hash", { $0.contentFingerprint = String(repeating: "b", count: 64) }),
      ("oversized hash", { $0.contentFingerprint = String(repeating: "x", count: 1_024) })
    ]
    for (label, mutate) in mutations {
      var corrupted = complete
      mutate(&corrupted.chunkRevisions![0])
      store.save(corrupted, key: key, session: session)
      precondition(store.load(key, duration: 1_801, session: session)?.segments == [first, second], "Provenance corruption lost text")
      precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session), "Corrupt \(label) accepted")
    }
    for revisions in [[old, old], [next, old]] {
      var corrupted = complete
      corrupted.chunkRevisions = revisions
      store.save(corrupted, key: key, session: session)
      precondition(store.load(key, duration: 1_801, session: session)?.chunkRevisions == nil)
    }
    var overlapping = complete
    overlapping.chunkRevisions![0].segmentCount = 2
    precondition(overlapping.validatedChunkRevisions(key: key) == nil)
    var wrongInterval = complete
    wrongInterval.chunkRevisions = nil
    wrongInterval.segments![0].timestamp = 901
    wrongInterval.segments![0].endTime = 902
    wrongInterval.segments![1].timestamp = 903
    wrongInterval.segments![1].endTime = 904
    precondition(wrongInterval.isValid(for: 1_801))
    wrongInterval.recordSettledChunk(index: 0, segmentRange: 0..<1, key: key)
    precondition(wrongInterval.chunkRevisions == nil, "Future-interval speech attributed to an earlier chunk")

    // Legacy ranges are not reconstructed from equal boundary timestamps.
    var legacy = complete
    legacy.chunkRevisions = nil
    store.save(legacy, key: key, session: session)
    precondition(store.load(key, duration: 1_801, session: session)?.chunkRevisions == nil)
    legacy.recordSettledChunk(index: 1, segmentRange: 1..<2, key: key)
    store.save(legacy, key: key, session: session)
    precondition(store.load(key, duration: 1_801, session: session)?.chunkRevisions == [next])
    precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session))

    let raw = SourceExtractionPersistence(directory: directory)
    let encoded = try JSONEncoder().encode(complete)
    var withoutRevisions = complete
    withoutRevisions.chunkRevisions = nil
    let oldSize = try JSONEncoder().encode(withoutRevisions).count
    let bounded = try complete.persistenceData(maximumBytes: oldSize)!
    let recovered = try JSONDecoder().decode(SourceMediaCheckpoint.self, from: bounded)
    precondition(recovered.segments == complete.segments && recovered.chunkRevisions == nil)
    let tooSmall = try complete.persistenceData(maximumBytes: oldSize - 1)
    let zero = try complete.persistenceData(maximumBytes: 0)
    precondition(tooSmall == nil && zero == nil, "Capacity fallback truncated text")
    let malformedValues: [Any] = ["invalid", ["unexpected": true], [["schemaVersion": 1]], NSNull()]
    for malformed in malformedValues {
      var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
      object["chunkRevisions"] = malformed
      raw.writePayload(key, data: try JSONSerialization.data(withJSONObject: object))
      let repaired = store.load(key, duration: 1_801, session: session)!
      precondition(repaired.segments == [first, second] && repaired.chunkRevisions == nil)
      precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session))
    }
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object.removeValue(forKey: "chunkRevisions")
    raw.writePayload(key, data: try JSONSerialization.data(withJSONObject: object))
    precondition(store.load(key, duration: 1_801, session: session)?.segments == [first, second])

    for altered in [
      try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "b", count: 64), suffix: "wav",
        locale: Locale(identifier: "ja-JP"), vocabulary: ["Memora"], pipeline: "recording-speech-analyzer-v1"),
      try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "a", count: 64), suffix: "wav",
        locale: Locale(identifier: "en-US"), vocabulary: ["Memora"], pipeline: "recording-speech-analyzer-v1"),
      try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "a", count: 64), suffix: "wav",
        locale: Locale(identifier: "ja-JP"), vocabulary: ["new glossary"], pipeline: "recording-speech-analyzer-v1"),
      try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "a", count: 64), suffix: "wav",
        locale: Locale(identifier: "ja-JP"), vocabulary: ["Memora"], pipeline: "different-pipeline")
    ] {
      store.save(complete, key: altered, session: session)
      precondition(store.load(altered, duration: 1_801, session: session)?.chunkRevisions == nil)
      precondition(!store.isCurrent(old, key: altered, duration: 1_801, session: session))
    }

    var blocks = SourceMediaCheckpoint(duration: 1_801, completedChunks: 1,
      blocks: [.init(text: "動画音声の確定発言", time: 900)])
    blocks.recordSettledChunk(index: 0, blockRange: 0..<1, key: key)
    let blockVersion = blocks.chunkRevisions!.first!
    store.save(blocks, key: key, session: session)
    precondition(store.isCurrent(blockVersion, key: key, duration: 1_801, session: session))
    blocks.blocks[0].text += "の訂正"
    store.save(blocks, key: key, session: session)
    precondition(!store.isCurrent(blockVersion, key: key, duration: 1_801, session: session))
    var silent = SourceMediaCheckpoint(duration: 1_801, completedChunks: 1, blocks: [], segments: [])
    silent.recordSettledChunk(index: 0, key: key)
    let silentVersion = silent.chunkRevisions!.first!
    store.save(silent, key: key, session: session)
    precondition(store.isCurrent(silentVersion, key: key, duration: 1_801, session: session))
    silent.completedChunks = 3
    store.save(silent, key: key, session: session)
    precondition(!store.isCurrent(silentVersion, key: key, duration: 1_801, session: session))

    store.save(complete, key: key, session: session)
    store.invalidate(fingerprints: [String(repeating: "a", count: 64)])
    precondition(!store.isCurrent(old, key: key, duration: 1_801, session: session))
    store.save(complete, key: key, session: session)
    precondition(store.load(key, duration: 1_801, session: store.begin()) == nil)
    let current = store.begin()
    store.save(complete, key: key, session: current)
    store.clear()
    precondition(!store.isCurrent(old, key: key, duration: 1_801, session: current))
    let unavailable = root.appendingPathComponent("revision-store-is-a-file")
    try Data([1]).write(to: unavailable)
    let failedStore = SourceMediaCheckpointStore(directory: unavailable)
    let failedSession = failedStore.begin()
    failedStore.save(complete, key: key, session: failedSession)
    precondition(!failedStore.isCurrent(old, key: key, duration: 1_801, session: failedSession))
    let expiringDirectory = root.appendingPathComponent("revision-expiry")
    let initial = SourceMediaCheckpointStore(directory: expiringDirectory, now: { Date(timeIntervalSince1970: 1_000) })
    initial.save(complete, key: key, session: initial.begin())
    let expired = SourceMediaCheckpointStore(directory: expiringDirectory,
      now: { Date(timeIntervalSince1970: 1_000 + SourceExtractionPersistence.retention + 1) })
    precondition(!expired.isCurrent(old, key: key, duration: 1_801, session: expired.begin()))
    print("SourceMediaChunkRevisionChecks: PASS. Real SQLite restart/current-revision checks, equal boundary timestamps with explicit ranges, append retention, 12 text/speaker/timing/recognition mutations, stable interval ID and changed content version, malformed/legacy provenance retains text without authority, overflow/overlap/order/source/configuration rejection, blocks/silence, deletion revokes old writers. No inference or upload.")
  }
}
