import Foundation

// Only state, persistence presentation and evidence invalidation are fixtures.
// Source storage/note operations, SQLite, file I/O and codecs are production code.
@MainActor
final class MemoraModel {
  var store: LocalStore
  var storeURL: URL
  var projectSources: [ProjectSource] = [] { didSet { projectSourceIndex.invalidate() } }
  var projectSourceIndex = IdentifiableIndex<ProjectSource>()
  var projectSourceProcessingIDs: Set<UUID> = []
  var spaces: [MemoraSpace] = []
  var currentTeamID: String? {
    didSet { if oldValue != currentTeamID { aiWorkspaceGeneration = UUID() } }
  }
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false
  var isStoreProtected = false
  var invalidated: [ProjectCitation.Target] = []
  var persistenceFailureMessage: String?
  var failurePresentation = PersistenceFailurePresentation()
  enum StorageKey { static let projectSources = "memoraProjectSources" }

  init(storeURL: URL) throws {
    self.storeURL = storeURL
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
  }

  func space(id: UUID) -> MemoraSpace? { spaces.first { $0.id == id } }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func invalidateProjectEvidence(_ targets: [ProjectCitation.Target]) { invalidated += targets }
  func handlingPersistenceFailureLocally<Value>(_ operation: () throws -> Value) rethrows -> Value {
    try failurePresentation.locallyHandled(operation)
  }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do {
      guard !isStoreProtected else { return false }
      try store.write(key, data: JSONEncoder().encode(value))
      return true
    } catch {
      if failurePresentation.shouldPresentGlobally { persistenceFailureMessage = "SQLite write failed" }
      return false
    }
  }
}
