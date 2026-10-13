import Foundation

/// Remembers each record's summary preview, so list rows do not re-read a long
/// summary on every redraw. An entry is reused only while the record's summary
/// is the very same string; comparing a string with itself is immediate, and
/// any edit produces a new one, so a stale preview is never shown.
enum SummaryPreviewCache {
  private final class Entry {
    let summary: String
    let preview: String
    init(summary: String, preview: String) {
      self.summary = summary
      self.preview = preview
    }
  }

  private static let entries: NSCache<NSUUID, Entry> = {
    let cache = NSCache<NSUUID, Entry>()
    cache.countLimit = 500
    cache.totalCostLimit = 8 * 1024 * 1024
    return cache
  }()

  static func preview(for id: UUID, summary: String, make: (String) -> String) -> String {
    if let entry = entries.object(forKey: id as NSUUID), entry.summary == summary {
      return entry.preview
    }
    let preview = make(summary)
    entries.setObject(Entry(summary: summary, preview: preview), forKey: id as NSUUID,
      cost: summary.utf8.count + preview.utf8.count)
    return preview
  }

  static func clear() { entries.removeAllObjects() }
}
