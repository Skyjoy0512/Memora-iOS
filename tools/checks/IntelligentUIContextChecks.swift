import Foundation

struct IntelligentUIContextChecks {
  @MainActor static func run(root: URL) async throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("interface-context.sqlite"))
    let task = MemoraTask(id: UUID(), title: "架空の確認", isCompleted: false)
    model.tasks = [task]
    model.message.interfaceTaskIDs = [task.id]
    model.message.interfaceWorkspaceID = nil
    let messageID = model.message.id
    let draft = MailDraft(recipients: [], subject: "確認", body: "架空本文", sourceMessageID: messageID)
    var other = draft; other.id = UUID(); other.sourceMessageID = UUID()
    model.mailDrafts = [draft, other]
    precondition(model.interfaceMailDraft(draft.id, messageID: messageID)?.id == draft.id)
    precondition(model.interfaceMailDraft(other.id, messageID: messageID) == nil)
    precondition(model.interfaceMailDraft(draft.id, messageID: UUID()) == nil)
    model.currentTeamID = "other"
    precondition(model.interfaceMailDraft(draft.id, messageID: messageID) == nil)
    precondition(model.interfaceRenderContext(messageID: messageID, taskIDs: [task.id]).taskIDs.isEmpty)
    model.currentTeamID = nil
    model.isRestoring = true; precondition(model.interfaceMailDraft(draft.id, messageID: messageID) == nil)
    model.isRestoring = false
    model.isStoreProtected = true; precondition(model.interfaceMailDraft(draft.id, messageID: messageID) == nil)
    model.isStoreProtected = false
    precondition(model.interfaceRenderContext(messageID: messageID, taskIDs: [task.id, UUID()]).taskIDs == [task.id])
    model.completeInterfaceTask(UUID(), messageID: messageID)
    precondition(model.interfaceCalls.isEmpty)
    model.completeInterfaceTask(task.id, messageID: messageID)
    await model.aiChatTask?.value
    precondition(model.interfaceCalls.count == 1 && model.interfaceCalls[0].name == "update_tasks")
    precondition(model.tasks[0] == task, "Dispatch fixture wrote task")
    // Removing the ephemeral grant simulates snapshot/history restoration.
    model.message.interfaceTaskIDs = []
    model.completeInterfaceTask(task.id, messageID: messageID)
    precondition(model.interfaceCalls.count == 1 && !model.canUseInterfaceTask(task.id, messageID: messageID))
    // Cloud permission changes invalidate even a known saved draft's UI context.
    var privacy = RecordPrivacy(classification: .personal); privacy.allowsCloudAI = true
    let person = Person(id: UUID(), name: "架空の人物", contactIdentifier: nil, privacy: privacy)
    model.people = [person]
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.recordCloudReads([.person(person.id)], messageID: messageID)
    precondition(model.interfaceMailDraft(draft.id, messageID: messageID) != nil)
    model.people[0].privacy.allowsCloudAI = false
    precondition(model.interfaceMailDraft(draft.id, messageID: messageID) == nil)
    print("IntelligentUIContextChecks: passed (production context/mail gates and task dispatch entry, current workspace/restore/protected state, foreign draft/message/UUID rejection, transient task grants, revoked cloud context; dispatch spy never writes)")
  }
}
