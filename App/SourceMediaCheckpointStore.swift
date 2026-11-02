import CryptoKit
import Foundation

/// Uses the bounded SQLite extraction-cache codec, not the backed-up record
/// store. Each instance serializes its persistence object under this lock.
final class SourceMediaCheckpointStore: @unchecked Sendable {
  static let shared = SourceMediaCheckpointStore(directory:
    SourceExtractionPersistence.directory.appendingPathComponent("MediaCheckpoints", isDirectory: true))

  private let lock = NSLock()
  private let persistence: SourceExtractionPersistence
  private var generation = UUID()

  init(directory: URL, now: @escaping () -> Date = Date.init) {
    persistence = SourceExtractionPersistence(directory: directory, now: now)
  }

  func begin() -> UUID {
    lock.lock()
    defer { lock.unlock() }
    return generation
  }

  static func key(fingerprint: String, suffix: String, locale: Locale, vocabulary: [String]) throws -> String {
    let configuration = try JSONEncoder().encode([vocabulary, [locale.identifier]])
    let hash = SHA256.hash(data: configuration).map { String(format: "%02x", $0) }.joined()
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return "media-v1.\(os.majorVersion).\(os.minorVersion).\(SourceMediaChunk.durationPerChunk).\(fingerprint).\(suffix).\(hash)"
  }

  func load(_ key: String, duration: TimeInterval, session: UUID) -> SourceMediaCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    guard session == generation, let data = persistence.readPayload(key) else { return nil }
    guard let checkpoint = try? JSONDecoder().decode(SourceMediaCheckpoint.self, from: data),
          checkpoint.isValid(for: duration) else {
      persistence.removePayload(key)
      return nil
    }
    if checkpoint.blocks.isEmpty,
       checkpoint.completedChunks == (try? SourceMediaChunk.plan(duration: duration).count) {
      persistence.removePayload(key)
      return nil
    }
    return checkpoint
  }

  func save(_ checkpoint: SourceMediaCheckpoint, key: String, session: UUID) {
    lock.lock()
    defer { lock.unlock() }
    guard session == generation, checkpoint.isValid(for: checkpoint.duration),
          let data = try? JSONEncoder().encode(checkpoint) else { return }
    // Silence is a reusable prefix, not a permanently cached failed import.
    if checkpoint.blocks.isEmpty,
       checkpoint.completedChunks == (try? SourceMediaChunk.plan(duration: checkpoint.duration).count) {
      persistence.removePayload(key)
      return
    }
    persistence.writePayload(key, data: data)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    generation = UUID()
    persistence.clear()
  }

  func invalidate(fingerprints: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    // A job may still be copying its input and not know its digest yet. Revoke
    // every old publishing session; unrelated jobs can still finish normally.
    generation = UUID()
    persistence.invalidate(fingerprints: fingerprints)
  }
}
