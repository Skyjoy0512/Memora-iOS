import Foundation

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
  @ObservationIgnored private static var failsNextWrite = false

  static func setFailureInjection(_ enabled: Bool) {
    failsNextWrite = enabled
  }

  private static func consumeInjectedFailure() throws {
    guard failsNextWrite else { return }
    failsNextWrite = false
    throw LocalStore.StoreError.statement(1)
  }
#endif

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
    let marker = key + ".migrated"
    guard UserDefaults.standard.data(forKey: marker) == nil else { return .absent }
    guard let legacy = UserDefaults.standard.data(forKey: key) else { return .absent }

    guard (try? LocalStore.shared.write(key, data: legacy)) != nil else {
      // The copy is still in UserDefaults and the marker is not written, so the
      // next launch tries again.
      return .failed
    }
    try? LocalStore.shared.write(marker, data: Data("1".utf8))
    return .data(legacy)
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
  static func encoded<T: Encodable>(_ value: T) throws -> Data {
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

  /// Saves on the caller's turn in the queue and reports whether it worked, for
  /// the places that must know before continuing. Waits for any earlier queued
  /// write, so ordering is preserved across both kinds of save.
  @discardableResult
  static func saveNow<T: Encodable>(_ value: T, key: String) throws {
    let data = try JSONEncoder().encode(value)
    try saveBatch([(key: key, data: data)])
  }

  /// Writes several documents in one transaction, so a logical operation that
  /// spans documents either lands completely or not at all.
  static func saveBatch(_ documents: [(key: String, data: Data)]) throws {
    try queue.sync {
#if DEBUG
      try consumeInjectedFailure()
#endif
      try LocalStore.shared.writeBatch(documents)
    }
  }

  /// Removes a document, waiting for any queued write so an older save cannot
  /// land after the removal.
  static func remove(_ key: String) throws {
    try queue.sync {
#if DEBUG
      try consumeInjectedFailure()
#endif
      try LocalStore.shared.remove(key)
    }
  }
}
