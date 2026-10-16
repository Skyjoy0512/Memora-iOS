import Foundation

@main
@MainActor
struct ProjectChatExecutionChecks {
  static func main() async {
    let model = MemoraModel()
    let id = UUID(), first = UUID(), second = UUID()
    let saved = ProjectChatTurn(role: .assistant, text: "保存済みの架空回答")
    model.projectChats = [ProjectChatThread(id: id, projectID: UUID(), title: "検証", messages: [saved], pendingMessageID: first)]
    let generation = model.aiWorkspaceGeneration
    install(model, id: id, requestID: first)
    precondition(model.projectChatExecutionIsCurrent(id, requestID: first, generation: generation))
    precondition(!model.projectChatExecutionIsCurrent(id, requestID: second, generation: generation))

    var releaseOld: CheckedContinuation<Void, Never>?
    let old = Task { @MainActor in
      await withCheckedContinuation { releaseOld = $0 }
      let current = model.projectChatExecutionIsCurrent(id, requestID: first, generation: generation)
      if current { model.projectChatPartialAnswers[id] = "古い応答" }
      model.finishProjectChatExecution(id, requestID: first)
      return current
    }
    model.projectChatJobs[id] = Task { _ = await old.value }
    while releaseOld == nil { await Task.yield() }
    model.cancelProjectChat(id)
    precondition(!model.projectChatBusyIDs.contains(id) && model.projectChatJobs[id] == nil)
    precondition(model.projectChatStages[id] == nil && model.projectChatPartialAnswers[id] == nil)
    precondition(model.projectChats[0].pendingMessageID == nil && model.projectChats[0].lastFailure?.contains("停止") == true)
    precondition(model.projectChats[0].messages == [saved])

    // A retry may start before the uncooperative old operation returns.
    model.projectChats[0].pendingMessageID = second
    install(model, id: id, requestID: second)
    let replacement = Task { @MainActor in await Task.yield() }
    model.projectChatJobs[id] = replacement
    releaseOld?.resume(); releaseOld = nil
    let oldWasCurrent = await old.value
    precondition(!oldWasCurrent && model.projectChatRequestIDs[id] == second)
    precondition(model.projectChatBusyIDs.contains(id) && model.projectChatJobs[id] != nil)
    precondition(model.projectChatStages[id] == "考えています" && model.projectChatPartialAnswers[id] == "新しい本文")

    let unrelated = UUID()
    model.projectChats.append(ProjectChatThread(id: unrelated, title: "完了済み", messages: [saved]))
    let unrelatedBefore = model.projectChats[1]
    model.invalidateAIWorkspaceExecution()
    let generationB = model.aiWorkspaceGeneration
    precondition(generationB != generation && model.projectChatRequestIDs.isEmpty && model.projectChatBusyIDs.isEmpty)
    precondition(model.projectChatJobs.isEmpty && model.projectChatPartialAnswers.isEmpty && model.projectChatStages.isEmpty)
    precondition(model.projectChats[0].pendingMessageID == nil && model.projectChats[0].messages == [saved])
    precondition(model.projectChats[0].lastFailure?.contains("ワークスペース") == true)
    precondition(model.projectChats[1] == unrelatedBefore)

    // Returning to the same workspace cannot make the old generation current.
    model.invalidateAIWorkspaceExecution()
    install(model, id: id, requestID: second)
    precondition(!model.projectChatExecutionIsCurrent(id, requestID: second, generation: generation))
    precondition(!model.projectChatExecutionIsCurrent(id, requestID: second, generation: generationB))
    precondition(model.projectChatExecutionIsCurrent(id, requestID: second, generation: model.aiWorkspaceGeneration))

    let cancelled = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return model.projectChatExecutionIsCurrent(id, requestID: second, generation: model.aiWorkspaceGeneration)
    }
    let cancelledWasCurrent = await cancelled.value
    precondition(!cancelledWasCurrent)

    let currentGeneration = model.aiWorkspaceGeneration
    model.projectChats[0].pendingMessageID = second
    let pendingBefore = model.projectChats[0]
    model.canPersist = false
    model.cancelProjectChat(id)
    precondition(model.projectChatRequestIDs.isEmpty && model.projectChatBusyIDs.isEmpty)
    precondition(model.projectChats[0] == pendingBefore)
    precondition(!model.projectChatExecutionIsCurrent(id, requestID: second, generation: currentGeneration))
    print("ProjectChatExecutionChecks: passed (real lifecycle extension, workspace generations, late cleanup, immediate retry, saved-history preservation, cancellation, failed persistence; memory fixtures only)")
  }

  private static func install(_ model: MemoraModel, id: UUID, requestID: UUID) {
    model.projectChatRequestIDs[id] = requestID
    model.projectChatBusyIDs.insert(id)
    model.projectChatStages[id] = "考えています"
    model.projectChatPartialAnswers[id] = "新しい本文"
  }
}

/// In-memory storage surface for the production execution extension; no records,
/// settings, credentials or model/network implementation are loaded.
@MainActor
final class MemoraModel {
  var aiWorkspaceGeneration = UUID()
  var projectChatRequestIDs: [UUID: UUID] = [:]
  var projectChatJobs: [UUID: Task<Void, Never>] = [:]
  var projectChatBusyIDs: Set<UUID> = []
  var projectChatStages: [UUID: String] = [:]
  var projectChatPartialAnswers: [UUID: String] = [:]
  var projectChats: [ProjectChatThread] = []
  var canPersist = true

  func projectChat(id: UUID) -> ProjectChatThread? { projectChats.first { $0.id == id } }

  func storeProjectChat(_ thread: ProjectChatThread) -> Bool {
    guard canPersist, let index = projectChats.firstIndex(where: { $0.id == thread.id }) else { return false }
    projectChats[index] = thread
    return true
  }
}
