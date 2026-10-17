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
    try checkNavigation(model, messageID: messageID)
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
    print("IntelligentUIContextChecks: passed (production context/mail/navigation gates and task dispatch entry, live membership/deletion, current workspace/restore/protected state, team-store isolation, foreign draft/document/message/UUID rejection, transient grants, revoked cloud context; dispatch spy never writes)")
  }

  @MainActor private static func checkNavigation(_ model: MemoraModel, messageID: UUID) throws {
    let meeting = Meeting(title: "架空の会議", participantIDs: nil, privacy: RecordPrivacy(classification: .personal))
    let project = FixtureSpace(id: UUID(), name: "架空の案件")
    let document = MemoraDocument(title: "架空の資料", kind: .document)
    model.meetings = [meeting]; model.spaces = [project]; model.documents = [document]
    model.message.sources = [AIChatSource(meetingID: meeting.id, title: meeting.title)]
    model.message.interfaceProjectIDs = [project.id]; model.message.documentIDs = [document.id]
    let targets: [AIInterfaceReferenceTarget] = [.meeting(meeting.id), .project(project.id), .document(document.id)]
    for target in targets {
      precondition(model.canOpenInterfaceReference(target, messageID: messageID))
      precondition(!model.canOpenInterfaceReference(target, messageID: UUID()))
    }
    for target in [AIInterfaceReferenceTarget.meeting(UUID()), .project(UUID()), .document(UUID())] {
      precondition(!model.canOpenInterfaceReference(target, messageID: messageID))
    }
    // A retained destination must recheck membership, not just the enclosing message.
    model.message.sources = []; model.message.interfaceProjectIDs = []; model.message.documentIDs = []
    for target in targets { precondition(!model.canOpenInterfaceReference(target, messageID: messageID)) }
    model.message.sources = [AIChatSource(meetingID: meeting.id, title: meeting.title)]
    model.message.interfaceProjectIDs = [project.id]; model.message.documentIDs = [document.id]
    model.meetings = []; model.spaces = []; model.documents = []
    for target in targets { precondition(!model.canOpenInterfaceReference(target, messageID: messageID)) }
    model.meetings = [meeting]; model.spaces = [project]; model.documents = [document]
    for protected in [true, false] {
      model.isStoreProtected = protected; model.isRestoring = !protected
      for target in targets { precondition(!model.canOpenInterfaceReference(target, messageID: messageID)) }
    }
    model.isRestoring = false
    model.currentTeamID = "team"; model.message.interfaceWorkspaceID = "team"
    precondition(!model.canUseInterfaceContext(messageID: messageID), "A matching team ID exposed personal SQLite")
    for target in targets { precondition(!model.canOpenInterfaceReference(target, messageID: messageID)) }
    model.currentTeamID = nil; model.message.interfaceWorkspaceID = nil
    model.documents[0].provenance = ArtifactProvenance(workspaceID: "other", sourceMessageID: messageID)
    precondition(!model.canOpenInterfaceReference(.document(document.id), messageID: messageID))
    model.documents[0].provenance = nil
    // A private record remains locally readable; this check never authorizes cloud export.
    precondition(model.canOpenInterfaceReference(.meeting(meeting.id), messageID: messageID))
    precondition(!model.allowsRecordAccess(meeting.id, purpose: .cloudAI))
    var permission = RecordPrivacy(classification: .personal); permission.allowsCloudAI = true
    model.meetings[0].privacy = permission
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.recordCloudReads([.meeting(meeting.id)], messageID: messageID)
    precondition(model.canOpenInterfaceReference(.meeting(meeting.id), messageID: messageID))
    model.meetings[0].privacy.allowsCloudAI = false
    for target in targets { precondition(!model.canOpenInterfaceReference(target, messageID: messageID)) }
    model.message.cloudProvenance = nil; model.message.cloudAuthorizationTargets = nil
    model.message.sources = []; model.message.interfaceProjectIDs = []; model.message.documentIDs = []
  }
}
