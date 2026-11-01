import Foundation

/// Nil fields follow the app's current defaults. Explicit choices belong to
/// this source; no provider credentials or submission permission are retained.
struct SourceSummaryOptions: Codable, Hashable, Sendable {
  var templateID: String?
  var length: SummaryLength?
  var engineChoice: SummaryEngineChoice?

  var isValid: Bool {
    templateID.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 512 } ?? true
  }
}
