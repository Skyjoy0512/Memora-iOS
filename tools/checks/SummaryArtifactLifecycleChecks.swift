import Foundation

/// Model fields are fixtures; the lifecycle methods, lease and SQLite are real.
@main @MainActor enum SummaryArtifactLifecycleChecks {
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(fileURL: directory.appendingPathComponent("records.sqlite"))
    try store.prepare()
    let cache = SummaryArtifactCache(store: store)
    let key = String(repeating: "b", count: 64), owner = UUID()
    let model = MemoraModel()
    let record = Meeting(id: owner)
    for mutation in 0..<10 {
      await cache.clear()
      let lease = cache.lease()
      await cache.write("settled", key: key, ownerID: owner, lease: lease)
      model.meetings = [record]
      switch mutation {
      case 0: model.meetings[0].transcript = ["edited"]
      case 1: model.meetings[0].title = "edited"
      case 2: model.meetings[0].createdAt = .now
      case 3: model.meetings[0].duration += 1
      case 4: model.meetings[0].spaceID = UUID()
      case 5: model.meetings[0].participantIDs = [UUID()]
      case 6: model.meetings[0].effectivePrivacy.allowsCloudAI.toggle()
      case 7: model.meetings = []
      case 8: model.meetings[0].summary = "human edit"
      default: break
      }
      model.invalidateSummaryArtifacts(previous: [record], cache: cache)
      let value = await cache.read(key, lease: lease)
      precondition((value == nil) == (mutation < 8))
    }
    let source = ProjectSource(id: owner)
    for mutation in 0..<10 {
      await cache.clear()
      let lease = cache.lease()
      await cache.write("settled", key: key, ownerID: owner, lease: lease)
      model.projectSources = [source]
      switch mutation {
      case 0: model.projectSources[0].extractedTextReference = "new-text"
      case 1: model.projectSources[0].contentFingerprint = "new-hash"
      case 2: model.projectSources[0].privacy.allowsCloudAI.toggle()
      case 3: model.projectSources[0].projectID = UUID()
      case 4: model.projectSources[0].title = "new-title"
      case 5: model.projectSources[0].originalURL = URL(string: "https://example.invalid/new")
      case 6: model.projectSources[0].textCoverage = "partial"
      case 7: model.projectSources[0].errorInformation = "missing pages"
      case 8: model.projectSources = []
      default: model.projectSources[0].summary = "human edit"
      }
      model.invalidateSummaryArtifacts(previous: [source], cache: cache)
      let value = await cache.read(key, lease: lease)
      precondition((value == nil) == (mutation < 9))
    }
    let llm = LLMSelection()
    precondition(model.summaryArtifactScope(ownerID: owner, privacy: record.effectivePrivacy, llm: llm) != nil)
    model.isStoreProtected = true
    precondition(model.summaryArtifactScope(ownerID: owner, privacy: record.effectivePrivacy, llm: llm) == nil)
    model.isStoreProtected = false; model.currentTeamID = "shared"
    precondition(model.summaryArtifactScope(ownerID: owner, privacy: record.effectivePrivacy, llm: llm) == nil)
    model.currentTeamID = nil; model.isRestoring = true
    precondition(model.summaryArtifactScope(ownerID: owner, privacy: record.effectivePrivacy, llm: llm) == nil)
    print("SummaryArtifactLifecycleChecks: PASS; production record/source invalidation methods with real SQLite and synchronous leases; body edits retained, source/permission/deletion invalidated, scope admission refused for protected/team/restore. Model state is a fixture.")
  }
}

@MainActor final class MemoraModel {
  var currentTeamID: String?
  var isStoreProtected = false
  var isRestoring = false
  var account: (email: String, name: String)?
  var meetings: [Meeting] = []
  var projectSources: [ProjectSource] = []
}
struct Meeting {
  var id: UUID
  var transcript = ["settled"]
  var title = "title"
  var createdAt = Date.distantPast
  var duration = 42.0
  var spaceID: UUID?
  var participantIDs: [UUID]?
  var effectivePrivacy = RecordPrivacy()
  var summary = "original"
}
struct ProjectSource {
  var id: UUID
  var extractedTextReference: String? = "text"
  var contentFingerprint: String? = "hash"
  var privacy = RecordPrivacy()
  var projectID: UUID?
  var title = "source"
  var originalURL: URL?
  var textCoverage = "complete"
  var errorInformation: String?
  var summary = "original"
}
struct LLMSelection { var keychainAccount = "synthetic" }
enum KeychainStore { static func string(forKey: String) -> String? { "synthetic-not-a-key" } }
