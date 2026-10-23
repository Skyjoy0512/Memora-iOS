import Foundation

// Only OS duration/media service boundaries and unrelated navigation/summary
// dependencies are fixtures. Import/Inbox/Meeting codecs and SQLite are real.
enum MediaFiles {
  static var directory: URL { AudioInbox.directory.deletingLastPathComponent().appendingPathComponent("recordings") }
  static var readDuration: @Sendable (URL) async -> TimeInterval? = { _ in 1.25 }
  static func duration(of url: URL) async -> TimeInterval? { await readDuration(url) }
  static func reference(for url: URL) -> String? {
    guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return nil }
    return url.lastPathComponent
  }
  static func resolve(_ name: String) -> URL? {
    guard !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { return nil }
    return directory.appendingPathComponent(name)
  }
  static func delete(_ url: URL?) -> Bool {
    guard let url else { return true }
    guard reference(for: url) != nil else { return false }
    do { try FileManager.default.removeItem(at: url); return true } catch { return false }
  }
  static func writePhoto(_ data: Data) -> String? { preconditionFailure("Photo migration is not under test") }
  @discardableResult static func deletePhoto(_ name: String) -> Bool { preconditionFailure("Photo migration is not under test") }
}

struct TemplateSummary: Hashable, Codable {}
enum SummaryPreviewCache {
  static func preview(for id: UUID, summary: String, build: (String) -> String) -> String { build(summary) }
}
enum MarkdownBlockParser {
  static func hasBlockStructure(_ text: String) -> Bool { false }
  static func overview(of text: String) -> String { text }
}
struct AudioImportTrashedRecord { var meeting: Meeting }
struct AudioImportTask { var id: UUID }
enum AudioImportDestination { case library }
enum AudioImportSection { case files }
enum AudioImportRoute { case meeting(UUID) }
struct AudioImportProcessing { var activeIDs: Set<UUID> = [] }
// The admission test does not parse a backup. The separate BackupRestoreChecks
// runner uses the real package/error types and install/rollback transaction.
enum BackupPackage {
  enum BackupError: Error, Equatable {
    case personalWorkspaceRequired, storeProtected, busy, notEmpty
  }
}
