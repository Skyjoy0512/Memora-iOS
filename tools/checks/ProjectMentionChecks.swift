import Foundation

@main
struct ProjectMentionChecks {
  @MainActor static func main() {
    let model = MemoraModel()
    let project = UUID(), other = UUID(), record = UUID(), foreign = UUID(), source = UUID()
    model.projects = [project, other]
    model.meetings = [.init(id: record, spaceID: project, displayTitle: "会議"), .init(id: foreign, spaceID: other, displayTitle: "他の会議")]
    model.projectSources = [.init(id: source, projectID: project, title: "設計資料")]
    model.allowed = [.meeting(record), .source(source)]
    precondition(model.projectMentionSelection(["record:" + foreign.uuidString], projectID: project) == nil)
    precondition(model.projectMentionSelection(["mcp:external"], projectID: project) == nil)
    precondition(model.projectMentionSelection(["service:notion"], projectID: project) == nil)
    precondition(model.projectMentionSelection(["skill:travel-plan"], projectID: project) == nil)
    let ids = ["record:" + record.uuidString, "source:" + source.uuidString]
    let selection = model.projectMentionSelection(ids, projectID: project)!
    precondition(selection.targets == [.meeting(record), .source(source)])
    precondition(selection.toolNames == ["read_record"])
    precondition(!selection.permits(.meeting(foreign)))
    precondition(model.projectMentionSelection(ids + ids, projectID: project) == selection)
    let skill = model.projectMentionSelection(["skill:project-reading"], projectID: project)!
    precondition(skill.toolNames == ProjectMentionSelection.readingTools && !skill.guidance.isEmpty)
    precondition(skill.targets == nil)
    model.disabled = ["read_record"]
    precondition(model.projectMentionSelection(["skill:project-reading"], projectID: project) == nil)
    precondition(model.projectMentionSelection(ids, projectID: project) == nil)
    precondition(!model.projectSourcePlugin(model.projectSources[0]).state.isReady)
    model.disabled = []
    model.allowed.remove(.source(source))
    precondition(model.projectMentionSelection(ids, projectID: project) == nil)
    model.allowed.insert(.source(source))
    model.projectSources[0].projectID = other
    precondition(model.projectMentionSelection(ids, projectID: project) == nil)
    model.currentTeamID = "another-workspace"
    precondition(model.projectMentionSelection([], projectID: project) == nil)
    print("ProjectMentionChecks passed: real resolver, cross-project denial, external/write denial, selected evidence, deduplication, skill guidance, disabled tools, revoked/moved sources, workspace change")
  }
}

// Only domain dependencies are fixtures. The catalog transformation and selection
// resolver above are compiled from the production model extension.
@MainActor final class MemoraModel {
  var projects: Set<UUID> = []
  var currentTeamID: String?
  var meetings: [FixtureRecord] = []
  var projectSources: [ProjectSource] = []
  var tasks: [FixtureTask] = []
  var allowed: Set<ProjectCitation.Target> = []
  var disabled: Set<String> = []
  var askAIConfiguration = FixtureConfiguration()
  var skillCatalog: [MemoraSkill] { MemoraSkill.bundled }
  func space(id: UUID) -> UUID? { projects.contains(id) ? id : nil }
  func meeting(id: UUID) -> FixtureRecord? { meetings.first { $0.id == id } }
  func toolRegistry() -> FixtureRegistry {
    FixtureRegistry(tools: Dictionary(uniqueKeysWithValues: ProjectMentionSelection.readingTools.map {
      ("memora:" + $0, FixtureTool(isEnabled: !disabled.contains($0)))
    }))
  }
  func pluginCatalog() -> [AIPlugin] {
    skillCatalog.map { skill in
      AIPlugin(id: "skill:" + skill.id, name: skill.name, summary: skill.summary, aliases: [], kind: .skill,
        state: Set(skill.toolNames).isDisjoint(with: disabled) ? .ready : .setup("disabled"),
        toolIDs: Set(skill.toolNames.map { "memora:" + $0 }), permissions: [], cost: .local, provider: .memora)
    } + [AIPlugin(id: "service:notion", name: "Notion", summary: "", aliases: [], kind: .connected,
      state: .ready, toolIDs: ["memora:save_to_notion"], permissions: [], cost: .unknown, provider: .directAPI)]
  }
  func projectEvidenceAllowed(_ target: ProjectCitation.Target, projectID: UUID, cloud: Bool) -> Bool {
    guard allowed.contains(target) else { return false }
    switch target {
    case .meeting(let id): return meeting(id: id)?.spaceID == projectID
    case .source(let id): return projectSources.first { $0.id == id }?.projectID == projectID
    default: return false
    }
  }
}
struct FixtureRecord { var id: UUID; var spaceID: UUID?; var displayTitle: String }
struct ProjectSource { var id: UUID; var projectID: UUID?; var title: String; var kindLabel: String { "note" }; var statusLabel: String { "ready" } }
struct FixtureTask { var id: UUID; var meetingID: UUID? }
struct FixtureTool { var isAvailable = true; var isEnabled: Bool }
struct FixtureRegistry { var tools: [String: FixtureTool] }
struct FixtureConfiguration { var engine = false }
enum AIEngineService { static func effectiveEngine(_ engine: Bool) -> FixtureEngine { .local } }
enum FixtureEngine { case local, cloud }
enum AgentTool: String { case readRecord = "read_record", listTasks = "list_tasks" }
struct AIToolDefinition { enum Provider { case memora, directAPI } }
struct AIPluginIcon { static func resolve(pluginID: String, name: String, iconIdentifier: String?) -> Self { Self() } }
