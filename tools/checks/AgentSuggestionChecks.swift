import Foundation

@main
struct AgentSuggestionChecks {
  @MainActor static func main() {
    let model = MemoraModel()
    let generic = model.agentPromptSuggestions
    precondition(generic.count == 3 && Set(generic.map(\.id)).count == 3)
    precondition(generic.allSatisfy { $0.sourceTitle == nil })
    precondition(model.stageAgentSuggestion(generic[0]))
    precondition(model.aiMessages.isEmpty && model.composerFocusRequest != nil)
    let draft = model.composerDraft
    precondition(!model.stageAgentSuggestion(generic[1]) && model.composerDraft == draft)
    model.composerDraft = ""
    model.composerAttachment = "existing attachment"
    precondition(!model.stageAgentSuggestion(generic[1]))
    model.composerAttachment = nil

    var permitted = Meeting(title: "実際の会議", createdAt: Date(timeIntervalSince1970: 10))
    permitted.privacy = RecordPrivacy(classification: .general)
    permitted.privacy.allowsCloudAI = true
    var privateRecord = Meeting(title: "PRIVATE_NO_CONSENT", createdAt: Date(timeIntervalSince1970: 20))
    privateRecord.privacy = RecordPrivacy(classification: .sensitive)
    var sample = permitted
    sample.id = SampleContent.sampleID
    sample.createdAt = Date(timeIntervalSince1970: 30)
    model.meetings = [privateRecord, sample, permitted]
    let personalized = model.agentPromptSuggestions
    precondition(personalized.allSatisfy { $0.sourceRecordID == permitted.id })
    precondition(!personalized.contains { $0.prompt.contains("PRIVATE_NO_CONSENT") })
    precondition(personalized[1].prompt.contains("宛先は推測せず") && personalized[1].prompt.contains("送信はしないで"))

    var task = MemoraTask(id: UUID(), title: "実際の未完了タスク", meetingID: permitted.id, isCompleted: false)
    model.tasks = [task]
    let taskSuggestion = model.agentPromptSuggestions[0]
    precondition(taskSuggestion.kind == .priorities && taskSuggestion.sourceTaskID == task.id)
    model.tasks[0].isCompleted = true
    precondition(!model.stageAgentSuggestion(taskSuggestion))
    task.id = SampleContent.sampleID
    model.tasks = [task]
    precondition(model.agentPromptSuggestions[0].kind == .tasks)
    model.tasks = []

    model.meetings[2].privacy.allowsCloudAI = false
    precondition(!model.stageAgentSuggestion(personalized[0]))
    precondition(model.agentPromptSuggestions.allSatisfy { $0.sourceTitle == nil })
    model.meetings[2] = permitted
    model.meetings[2].title = "Changed after presentation"
    precondition(!model.stageAgentSuggestion(personalized[0]))
    model.meetings = []
    precondition(!model.stageAgentSuggestion(personalized[0]))

    model.currentTeamID = "team"
    precondition(model.agentPromptSuggestions.isEmpty && !model.stageAgentSuggestion(generic[0]))
    model.currentTeamID = nil
    model.aiPersonScopeID = UUID()
    precondition(model.agentPromptSuggestions.isEmpty)
    model.aiPersonScopeID = nil
    model.isRestoring = true
    precondition(model.agentPromptSuggestions.isEmpty)
    model.isRestoring = false
    model.isStoreProtected = true
    precondition(model.agentPromptSuggestions.isEmpty)
    model.isStoreProtected = false
    model.aiMessages = ["settled conversation"]
    precondition(!model.stageAgentSuggestion(generic[0]))
    model.aiMessages = []
    model.isAIChatResponding = true
    precondition(!model.stageAgentSuggestion(generic[0]))

    let bounded = AgentPromptSuggestion.make(recordID: permitted.id, recordTitle: "\n" + String(repeating: "字", count: 500))
    precondition((bounded[0].sourceTitle?.count ?? 0) <= 100)
    precondition(AgentPromptSuggestion.make(recordTitle: "orphan").allSatisfy { $0.sourceTitle == nil })
    precondition(AgentPromptSuggestion.make(recordID: permitted.id, recordTitle: "  \n ").allSatisfy { $0.sourceRecordID == nil })
    print("Agent suggestions: production builder/model staging, privacy, workspace, samples, stale sources and draft protection passed")
  }
}
