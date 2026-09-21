import Foundation

/// Reads and writes the app's documents. Keeping this here means the model asks
/// for records and never deals with the store, encoding, or the move off
/// `UserDefaults` itself.
@MainActor
enum RecordStore {
  private static let queue = DispatchQueue(label: "app.memora.persistence", qos: .utility)

  /// Opens the store. Safe to call more than once.
  static func prepare() {
    try? LocalStore.shared.prepare()
  }

  /// Reads a stored document, moving a legacy `UserDefaults` copy across the
  /// first time. The old value is left in place as a safety copy.
  static func read(_ key: String) -> Data? {
    if let data = LocalStore.shared.read(key) { return data }
    guard let legacy = UserDefaults.standard.data(forKey: key) else { return nil }
    try? LocalStore.shared.write(key, data: legacy)
    return legacy
  }

  /// Keeps an unreadable document aside, so it can be inspected or recovered
  /// instead of being replaced.
  static func quarantine(_ data: Data, key: String) {
    try? LocalStore.shared.write(key + ".unreadable", data: data)
    try? LocalStore.shared.remove(key)
  }

  /// Saves off the main thread. `onFailure` runs on the main actor when the
  /// document could not be written.
  static func save<T: Encodable & Sendable>(
    _ value: T,
    key: String,
    onFailure: (@MainActor () -> Void)? = nil
  ) {
    queue.async {
      guard let data = try? JSONEncoder().encode(value) else { return }
      do {
        try LocalStore.shared.write(key, data: data)
      } catch {
        Task { @MainActor in onFailure?() }
      }
    }
  }

  /// Saves on the caller's actor and reports whether it worked, for the few
  /// places that need to know before continuing.
  @discardableResult
  static func saveNow<T: Encodable>(_ value: T, key: String) -> Bool {
    guard let data = try? JSONEncoder().encode(value) else { return false }
    do {
      try LocalStore.shared.write(key, data: data)
      return true
    } catch {
      return false
    }
  }

  static func remove(_ key: String) {
    try? LocalStore.shared.remove(key)
  }
}
