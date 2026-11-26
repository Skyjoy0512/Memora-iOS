import Foundation

@main @MainActor
struct AgentOutcomeChecks {
  static func main() async {
    for accepts in [false, true] {
      let model = MemoraModel()
      let approval = AgentApproval(messageID: model.aiMessages[1].id)
      let operation = Task { await model.requestAgentApproval(approval) }
      while model.agentApprovalWaiter.pendingID != approval.id { await Task.yield() }
      model.agentApprovalWaiter.resolve(accepts, id: approval.id)
      let result = await operation.value
      precondition(result == accepts && !model.aiMessages[1].didChangeData && !model.aiMessages[1].hasUnconfirmedDataChange)
      precondition(model.canRetryAIAnswer(approval.messageID))
    }
    for (outcome, retries) in [(AgentToolOutcome(text: "保存失敗", isError: true), true),
                             (.init(text: "読めました"), true), (.init(text: "重複のため変更なし"), true),
                             (.init(text: "", dataChange: .committed), false),
                             (.init(text: "外部結果不明", isError: true, dataChange: .unconfirmed), false),
                             (.init(text: "一部保存", isError: true, dataChange: .committed), false)] {
      let model = MemoraModel(); model.toolOutcome = outcome
      let id = model.aiMessages[1].id
      _ = await model.runAgentTool(.init(id: "call", name: "fixture", arguments: [:]), messageID: id, scope: .all)
      precondition(model.canRetryAIAnswer(id) == retries)
      precondition(model.aiMessages[1].didChangeData == (outcome.dataChange == .committed))
      precondition(model.aiMessages[1].hasUnconfirmedDataChange == (outcome.dataChange == .unconfirmed))
      // A subsequent read/failure never erases earlier confirmed or uncertain effects.
      model.toolOutcome = .init(text: "後続の読み取り")
      _ = await model.runAgentTool(.init(id: "later", name: "fixture", arguments: [:]), messageID: id, scope: .all)
      precondition(model.canRetryAIAnswer(id) == retries)
    }
    for saves in [false, true] {
      let model = MemoraModel(); model.saveSucceeds = saves
      let id = model.aiMessages[1].id
      let project = await model.createProjectTool(.init(id: "project", name: "create_project", arguments: ["name": "新規"]), messageID: id)
      precondition(project.isError == !saves && project.dataChange == (saves ? .committed : .none))
      let journal = await model.addJournalMemoTool(.init(id: "journal", name: "add_journal_memo", arguments: ["body": "本文"]), messageID: id)
      precondition(journal.isError == !saves && journal.dataChange == (saves ? .committed : .none))
      let memory = await model.saveMemoryTool(.init(id: "memory", name: "save_memory", arguments: ["text": "覚える内容"]), messageID: id)
      precondition(memory.isError == !saves && memory.dataChange == (saves ? .committed : .none))
    }
    let duplicate = MemoraModel(); duplicate.visibleAIMemories = [.init(text: "覚える内容")]
    let noChange = await duplicate.saveMemoryTool(.init(id: "memory", name: "save_memory", arguments: ["text": "覚える内容"]), messageID: duplicate.aiMessages[1].id)
    precondition(!noChange.isError && noChange.dataChange == .none)
    duplicate.spaces = [.init(name: "既存")]
    let existing = await duplicate.createProjectTool(.init(id: "project", name: "create_project", arguments: ["name": "既存"]), messageID: duplicate.aiMessages[1].id)
    precondition(!existing.isError && existing.dataChange == .none)
    let history = MemoraModel()
    let citation = ProjectCitation(target: .meeting(UUID()), title: "記録の写真", excerpt: "写真の文字",
      photo: .init(name: "fixture.jpg", byteCount: 1, modifiedAt: .now, textReadAt: .now))
    history.aiMessages = [
      AIChatMessage(role: .user, text: "質問"),
      AIChatMessage(role: .assistant, text: "通常の履歴"),
      AIChatMessage(role: .assistant, text: "写真由来の回答", sourceCitations: [citation]),
      AIChatMessage(role: .assistant, text: "生成途中", isThinking: true),
    ]
    precondition(history.aiConversationContext() == "利用者: 質問\n回答: 通常の履歴")
    print("PASS: production approval/aggregation/retry methods, confirmed/failed/partial/unknown/read-only/no-op outcomes, sticky retry barriers, and memory/project/journal tool save branches; storage/provider boundaries are fixtures.")
  }
}

@MainActor final class MemoraModel {
  var aiMessages = [AIChatMessage(role: .user), AIChatMessage(role: .assistant)]
  var isAIChatResponding = false
  var agentApprovalWaiter = AgentInteractionWaiter<Bool>()
  var pendingAgentApproval: AgentApproval?
  var toolOutcome = AgentToolOutcome(text: "")
  var saveSucceeds = true
  var spaces: [Space] = []
  var visibleAIMemories: [Memory] = []
  var isAIMemoryEnabled = true
  var cloudMemoryFingerprint = "fixture"
  var aiConversationID = UUID()
  static let aiMemoryCharacterLimit = 100
  static let declinedOutcome = AgentToolOutcome(text: "拒否")
  func gmailResultsAreCurrent(_ id: UUID) -> Bool { true }
  func isCloudSessionAuthorized(_ id: UUID) -> Bool { true }
  func agentMessage(_ id: UUID) -> AIChatMessage? { aiMessages.first { $0.id == id } }
  func updateAgentMessage(_ id: UUID, _ update: (inout AIChatMessage) -> Void) {
    guard let i = aiMessages.firstIndex(where: { $0.id == id }) else { return }; update(&aiMessages[i])
  }
  func performAgentTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope, compact: Bool, automaticAccess: Bool) async -> AgentToolOutcome { toolOutcome }
  func approve(tool: AgentTool, title: String, lines: [String], confirmTitle: String, messageID: UUID) async -> UUID? { UUID() }
  func addSpace(name: String) -> UUID? { saveSucceeds ? UUID() : nil }
  func addAIMemory(_ text: String, origin: Origin, sourceReference: String) -> Bool { saveSucceeds && !visibleAIMemories.contains { $0.text == text } }
  func finishAgentStep(_ id: UUID, on: UUID, state: State, detail: String? = nil) {}
  func addLifeLogEntry(kind: Kind, title: String, summary: String, createdAt: Date, photoData: Data?, eventDate: Date?, locationName: String?) -> Bool { saveSucceeds }
  enum Origin { case agent }; enum State { case done, failed }; enum Kind { case memo }
}
struct AIChatMessage {
  enum Role { case user, assistant }
  var role: Role
  var text = ""
  var id = UUID(); var didChangeData = false; var hasUnconfirmedDataChange = false
  var residentName: String?; var attachment: String?; var cloudProvenance: Provenance?
  var agentSteps: [Step] = []
  var sourceCitations: [ProjectCitation] = []
  var isThinking = false
  struct Provenance { var memoryFingerprint: String }
  struct Step { var output: [String] = [] }
}
struct AgentApproval { var id = UUID(); var messageID: UUID }
enum AIChatScope { case all }
enum AgentTool { case saveMemory, createProject, addJournalMemo }
struct Memory { var text: String }
struct Space { var id = UUID(); var name: String }
