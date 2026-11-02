import Foundation

/// Keeps the text someone is still writing, so a draft survives leaving the
/// screen or the app being stopped before it is saved. Writes go through the
/// same ordered store as the records, so a draft that is cleared cannot come
/// back from an older save that was still on its way.
///
/// A draft is stored as its own UTF-8 text behind a one-byte format marker, and
/// read back the same way. Earlier builds wrote a JSON string but read the raw
/// bytes, so quotes and newline escapes showed up in the body; `decode` reads
/// that old form once, here, instead of handing it back as text.
@MainActor
enum DraftStore {
  private static let prefix = "draft."
  private static let textFormatMarker: UInt8 = 0x01

  static func storageKey(for key: String) -> String { prefix + key }

  enum LoadOutcome: Equatable {
    case absent, unreadable
    case text(String)

    var text: String? {
      if case .text(let value) = self { return value }
      return nil
    }
  }

  /// An unreadable draft must not become an empty editor that overwrites it.
  static func read(_ key: String) -> LoadOutcome {
    switch RecordStore.load(storageKey(for: key)) {
    case .absent: return .absent
    case .failed: return .unreadable
    case .data(let data):
      return decode(data).map(LoadOutcome.text) ?? .unreadable
    }
  }

  static func load(_ key: String) -> String? {
    read(key).text
  }

  static func save(_ text: String, key: String) {
    RecordStore.saveData(encode(text), key: prefix + key)
  }

  /// Saves and waits for the write, for callers that must know the draft landed
  /// before they continue. Throws when it could not be stored.
  static func saveAndWait(_ text: String, key: String) throws {
    try RecordStore.saveDataNow(encode(text), key: prefix + key)
  }

  /// Removes the draft, waiting for any queued save of it so the two cannot
  /// arrive out of order. The committed text is what matters; the draft is only
  /// a safety copy, so a failure here is not reported as a lost record.
  static func clear(_ key: String) {
    try? RecordStore.remove(prefix + key)
  }

  private static func encode(_ text: String) -> Data {
    var data = Data([textFormatMarker])
    data.append(contentsOf: text.utf8)
    return data
  }

  private static func decode(_ data: Data) -> String? {
    if data.first == textFormatMarker {
      return String(data: Data(data.dropFirst()), encoding: .utf8)
    }
    // The old writer stored a JSON-encoded string; decoding it recovers the
    // original text without the quotes and escapes that leaked before.
    return try? JSONDecoder().decode(String.self, from: data)
  }
}
