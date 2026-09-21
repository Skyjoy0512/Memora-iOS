import Foundation

/// Keeps the text someone is still writing, so a draft survives leaving the
/// screen or the app being stopped before it is saved. Writes go through the
/// same ordered store as the records, so a draft that is cleared cannot come
/// back from an older save that was still on its way.
@MainActor
enum DraftStore {
  private static let prefix = "draft."

  static func load(_ key: String) -> String? {
    guard case .data(let data) = RecordStore.load(prefix + key),
          let text = String(data: data, encoding: .utf8) else {
      return nil
    }
    return text
  }

  static func save(_ text: String, key: String) {
    RecordStore.save(text, key: prefix + key)
  }

  /// Removes the draft, waiting for any queued save of it so the two cannot
  /// arrive out of order. The committed text is what matters; the draft is only
  /// a safety copy, so a failure here is not reported as a lost record.
  static func clear(_ key: String) {
    try? RecordStore.remove(prefix + key)
  }
}
