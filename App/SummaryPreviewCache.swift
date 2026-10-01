import Foundation
import Synchronization

/// Remembers each record's summary preview, so list rows do not re-read a long
/// summary on every redraw. An entry is reused only while the record's summary
/// is the very same string; comparing a string with itself is immediate, and
/// any edit produces a new one, so a stale preview is never shown.
enum SummaryPreviewCache {
  private struct Entry {
    var summary: String
    var preview: String
  }

  private static let entries = Mutex<[UUID: Entry]>([:])

  static func preview(for id: UUID, summary: String, make: (String) -> String) -> String {
    if let entry = entries.withLock({ $0[id] }), entry.summary == summary {
      return entry.preview
    }
    let preview = make(summary)
    entries.withLock { $0[id] = Entry(summary: summary, preview: preview) }
    return preview
  }
}
