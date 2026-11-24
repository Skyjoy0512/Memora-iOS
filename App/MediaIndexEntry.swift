import Foundation

/// What the app knows about one stored photo. The file is the truth: an entry
/// whose file is gone is dropped, and metadata that disagrees with the file is
/// read again rather than trusted. The text is read on this device only.
struct MediaIndexEntry: Codable, Hashable, Identifiable, Sendable {
  static let storageKey = "memora.mediaIndex.v1"
  static let maximumEntries = 2_000
  static let maximumText = 8_000

  var name: String
  var recordID: UUID
  var recordTitle: String
  var recordDate: Date
  var byteCount: Int
  var pixelWidth: Int
  var pixelHeight: Int
  /// Text recognized in the image; empty until a read has run.
  var text: String = ""
  /// Set when a read finished, so a photo with nothing written on it is not
  /// read again on every visit.
  var textReadAt: Date?

  var id: String { name }

  /// Matches the record's title or the words found inside the photo. Both sides
  /// fold width and case, so a half-width search finds full-width text.
  func matches(_ query: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return true }
    return recordTitle.localizedStandardContains(needle) || text.localizedStandardContains(needle)
  }
}
