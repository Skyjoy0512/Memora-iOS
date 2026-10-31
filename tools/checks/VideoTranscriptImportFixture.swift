import Foundation

// State/navigation and the RecordStore queue are fixtures; import, context, Meeting codec and SQLite are real.
@MainActor final class MemoraModel {
  var meetings: [Meeting] = []
  var projectSources: [ProjectSource] = []
  var spaces: [MemoraSpace] = []
  var currentTeamID: UUID?
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var store: LocalStore
  enum StorageKey { static let meetings = "meetings"; static let projectSources = "sources" }
  init(_ url: URL) throws { store = LocalStore(fileURL: url); try store.prepare() }
  func source(id: UUID) -> ProjectSource? { projectSources.first { $0.id == id } }
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func invalidateProjectEvidence(_ targets: [ProjectCitation.Target]) {}
  func persistBatch(_ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do { try store.applyBatch(writes: build(), removing: []); return true } catch { return false }
  }
}
enum RecordStore { static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) } }
