import CryptoKit
import Foundation

enum SourceMediaCheckpointChecks {
  static func run(root: URL) throws {
    let directory = root.appendingPathComponent("media-checkpoints")
    let store = SourceMediaCheckpointStore(directory: directory)
    let original = root.appendingPathComponent("checkpoint-input.mp4")
    try Data("immutable media fixture".utf8).write(to: original)
    let copies = root.appendingPathComponent("media-snapshot", isDirectory: true)
    try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: false)
    let snapshot = try SourceMediaSnapshot(original, directory: copies)
    let key = try SourceMediaCheckpointStore.key(fingerprint: snapshot.fingerprint, suffix: "mp4",
      locale: Locale(identifier: "ja-JP"), vocabulary: ["Memora"])
    let otherLanguage = try SourceMediaCheckpointStore.key(fingerprint: snapshot.fingerprint, suffix: "mp4",
      locale: Locale(identifier: "en-US"), vocabulary: ["Memora"])
    let otherTerms = try SourceMediaCheckpointStore.key(fingerprint: snapshot.fingerprint, suffix: "mp4",
      locale: Locale(identifier: "ja-JP"), vocabulary: ["別の用語"])
    precondition(key != otherLanguage && key != otherTerms)
    let session = store.begin()
    let silentPrefix = SourceMediaCheckpoint(duration: 1_801, completedChunks: 1, blocks: [])
    store.save(silentPrefix, key: key, session: session)
    let restarted = SourceMediaCheckpointStore(directory: directory)
    let restoredSilence = restarted.load(key, duration: 1_801, session: restarted.begin())
    precondition(restoredSilence?.completedChunks == 1 && restoredSilence?.blocks.isEmpty == true)

    var prefix = SourceMediaCheckpoint(duration: 1_801, completedChunks: 2,
      blocks: [.init(text: "後半の発言", time: 915)])
    store.save(prefix, key: key, session: session)
    let loaded = restarted.load(key, duration: 1_801, session: restarted.begin())!
    precondition(loaded.blocks == prefix.blocks && loaded.completedChunks == 2)
    var transcript = SourceMediaTranscript()
    try transcript.restore(loaded.blocks)
    let tail = try SourceMediaChunk.plan(duration: 1_801)[2]
    try transcript.append([TranscriptSegment(id: UUID(), speaker: "", speakerIsCertain: false,
      timestamp: 0.5, text: "最後の発言")], chunk: tail)
    precondition(transcript.blocks.last?.time == 1_800.5)

    prefix.blocks = [.init(text: "未来の区間を完了扱いしない", time: 1_801)]
    precondition(!prefix.isValid(for: 1_801))
    prefix.blocks = [.init(text: "不正時刻", time: .nan)]
    precondition(!prefix.isValid(for: 1_801))
    let allSilent = SourceMediaCheckpoint(duration: 1_801, completedChunks: 3, blocks: [])
    store.save(allSilent, key: key, session: session)
    precondition(store.load(key, duration: 1_801, session: session) == nil)

    // Revocation also covers a session that had not hashed its original yet.
    let beforeHash = store.begin()
    store.save(silentPrefix, key: key, session: beforeHash)
    store.invalidate(fingerprints: [snapshot.fingerprint])
    store.save(silentPrefix, key: key, session: beforeHash)
    store.save(silentPrefix, key: otherLanguage, session: beforeHash)
    precondition(store.load(key, duration: 1_801, session: store.begin()) == nil)
    precondition(store.load(otherLanguage, duration: 1_801, session: store.begin()) == nil)

    let current = store.begin()
    store.save(silentPrefix, key: key, session: current)
    let unrelated = try SourceMediaCheckpointStore.key(fingerprint: String(repeating: "b", count: 64),
      suffix: "mp4", locale: Locale(identifier: "ja-JP"), vocabulary: [])
    store.save(silentPrefix, key: unrelated, session: current)
    store.invalidate(fingerprints: [snapshot.fingerprint])
    precondition(store.load(unrelated, duration: 1_801, session: store.begin()) != nil)
    store.clear()
    store.save(silentPrefix, key: key, session: current)
    precondition(store.load(key, duration: 1_801, session: store.begin()) == nil)

    let raw = SourceExtractionPersistence(directory: directory)
    raw.writePayload(key, data: Data("corrupt JSON".utf8))
    precondition(store.load(key, duration: 1_801, session: store.begin()) == nil)
    precondition(raw.readPayload(key) == nil)

    let modified = try original.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
    try Data("different media fixture".utf8).write(to: original)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: original.path)
    do { try snapshot.verifyOriginal(); preconditionFailure("Changed original was accepted") }
    catch ProjectSourceFiles.Failure.invalidFile { }
    let copiedBytes = try Data(contentsOf: snapshot.url)
    let changedBytes = try Data(contentsOf: original)
    precondition(copiedBytes.count == changedBytes.count && copiedBytes != changedBytes)
  }
}
