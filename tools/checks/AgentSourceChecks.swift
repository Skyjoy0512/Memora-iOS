import Foundation

@main struct AgentSourceChecks {
  @MainActor static func main() async {
    let model = MemoraModel()
    let projectID = UUID(), id = UUID(), messageID = UUID()
    model.projects = [projectID]
    var privacy = RecordPrivacy(classification: .general, allowsCloudAI: true)
    let source = ProjectSource(id: id, projectID: projectID, title: "提案書", extractedTextReference: "fixture", privacy: privacy)
    model.projectSources = [source]
    ProjectSourceTextReader.read = { [.init(text: "架空の根拠", page: 2)] }
    let result = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(!result.isError && result.text.contains("ページ2") && model.message.projectSourceReferences.count == 1)
    model.currentTeamID = "different-workspace"
    let team = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(team.isError)
    model.currentTeamID = nil
    let policy = AIPluginExecutionPolicy(pluginIDs: ["record:other"], toolIDs: ["memora:read_record"], recordIDs: [UUID()], limitsRecordReads: true)
    model.agentPluginPolicies[messageID] = policy
    let scoped = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(scoped.isError)
    model.agentPluginPolicies[messageID] = AIPluginExecutionPolicy(pluginIDs: ["record:" + id.uuidString], toolIDs: ["memora:read_record"], recordIDs: [id], limitsRecordReads: true)
    let collidingID = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(collidingID.isError)
    model.agentPluginPolicies = [:]
    privacy.revokeExternalPermissions(); model.projectSources[0].privacy = privacy
    let denied = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(denied.isError)
    model.projectSources = [source]
    ProjectSourceTextReader.read = { model.projectSources = []; return [.init(text: "失効した内容")] }
    let revoked = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(revoked.isError && !revoked.text.contains("失効した内容"))
    model.projectSources = [source]
    ProjectSourceTextReader.read = { model.projectSources[0].title = "編集された資料"; return [.init(text: "古い内容")] }
    let changed = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: false)
    precondition(changed.isError)
    let automatic = await model.readAgentProjectSource(id, messageID: messageID, compact: false, automatic: true)
    precondition(automatic.isError)
    print("AgentSourceChecks: passed (production extension, individual grant, page/source provenance, selected IDs, workspace, revoke/edit during suspended read, automatic refusal; no files/network)")
  }
}

struct ProjectSource: Codable, Hashable {
  var id: UUID
  var projectID: UUID?
  var title: String
  var extractedTextReference: String?
  var privacy: RecordPrivacy
  var canProvideText = true
}

@MainActor enum ProjectSourceTextReader {
  static var read: () async throws -> [ProjectSourceText] = { [] }
  static func readAsync(_ name: String) async throws -> [ProjectSourceText] { try await read() }
}

struct MockSourceMessage { var projectSourceReferences: [AgentSourceReference] = [] }

@MainActor final class MemoraModel {
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var projectSources: [ProjectSource] = []
  var projects: Set<UUID> = []
  var agentPluginPolicies: [UUID: AIPluginExecutionPolicy] = [:]
  var message = MockSourceMessage()
  func source(id: UUID) -> ProjectSource? { projectSources.first { $0.id == id } }
  func space(id: UUID) -> UUID? { projects.contains(id) ? id : nil }
  func updateAgentMessage(_ id: UUID, change: (inout MockSourceMessage) -> Void) { change(&message) }
  func markCloudProvenanceIncomplete(_ id: UUID) {}
  static func questionWords(in query: String) -> [String] { [query] }
}
