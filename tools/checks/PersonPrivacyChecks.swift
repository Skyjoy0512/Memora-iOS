import Foundation
import SQLite3

@main struct PersonPrivacyChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraPersonPrivacy-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("records.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    var person = Person(id: UUID(), name: "田中 太郎", note: "架空の人物メモ", contactIdentifier: "private-contact-id", photoData: Data([1, 2, 3]))
    let other = Person(id: UUID(), name: person.name, note: "別人の非公開メモ", contactIdentifier: nil)
    model.people = [person, other]
    model.glossaryTerms = [" 業務用語 ", "業務用語"]
    model.spaces = [FixtureSpace(id: UUID(), name: "非公開プロジェクト名")]
    precondition(model.processingVocabulary(external: true) == ["業務用語"])
    precondition(model.processingVocabulary(external: false).contains(person.name))
    precondition(model.processingVocabulary(external: false).contains("非公開プロジェクト名"))
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(person)) as! [String: Any]
    legacy.removeValue(forKey: "privacy")
    let old = try JSONDecoder().decode(Person.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.id == person.id && old.photoData == person.photoData && old.contactIdentifier == person.contactIdentifier)
    precondition(old.privacy.classification == .personal && !old.privacy.allowsCloudAI && !old.privacy.allowsAutomaticAgentAccess)
    let exported = try JSONEncoder().encode(PersonAIContext(person))
    let exportKeys = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
    precondition(exportKeys["contactIdentifier"] == nil && exportKeys["photoData"] == nil)
    precondition(PersonAIContext(Person(id: UUID(), name: String(repeating: "人", count: 300), note: String(repeating: "文", count: 3_000), contactIdentifier: nil)).note?.count == 2_000)

    let messageID = UUID()
    func resetMessage() {
      model.message = FixtureMessage(cloudProvenance: model.newCloudProvenance(references: []), cloudAuthorizationTargets: [])
    }
    func readPerson(_ id: UUID = person.id, automatic: Bool = false) -> AgentToolOutcome {
      model.readPersonTool(.init(id: "read", name: "read_person", arguments: ["person_id": id.uuidString]),
        messageID: messageID, compact: false, purpose: automatic ? .automaticAgent : .cloudAI)
    }
    resetMessage()
    let blocked = readPerson()
    precondition(blocked.isError && !blocked.text.contains(person.name) && !blocked.text.contains(person.note!) && model.reads.isEmpty)
    let localRead = model.readPersonTool(.init(id: "local", name: "read_person", arguments: ["person_id": person.id.uuidString]),
      messageID: messageID, compact: true, purpose: .onDeviceAI)
    precondition(!localRead.isError && localRead.text.contains(person.note!) && model.reads.isEmpty)
    precondition(!model.canReuseCloudConversation(model.message.cloudProvenance))
    resetMessage()
    let general = RecordPrivacy(classification: .general, allowsCloudAI: true)
    let tooLow = await model.setRecordPrivacy(general, target: .person(person.id)); precondition(!tooLow)
    person.privacy = general; model.people[0] = person
    precondition(!model.allowsPersonAccess(person.id, purpose: .cloudAI))
    let cloudGrant = RecordPrivacy(classification: .personal, allowsCloudAI: true, allowsAutomaticWebhook: true, allowsTeamSharing: true)
    let granted = await model.setRecordPrivacy(cloudGrant, target: .person(person.id)); precondition(granted)
    precondition(model.people[0].privacy.allowsCloudAI && !model.people[0].privacy.allowsAutomaticWebhook && !model.people[0].privacy.allowsTeamSharing)
    precondition(!model.allowsPersonAccess(person.id, purpose: .automaticAgent) && !model.supportsTeamPermission(.person(person.id)))
    resetMessage()
    let permitted = readPerson()
    precondition(!permitted.isError && permitted.text.contains(person.note!) && !permitted.text.contains("private-contact-id"))
    precondition(Set(model.reads) == [.person(person.id)] && model.message.cloudProvenance?.isComplete == true)
    precondition(model.isCloudSessionAuthorized(messageID) && model.canReuseCloudConversation(model.message.cloudProvenance))
    let captured = model.message.cloudProvenance!
    let capturedReference = model.recordReference(for: .person(person.id))!
    let encoded = try JSONEncoder().encode(captured)
    let decoded = try JSONDecoder().decode(AIConversationProvenance.self, from: encoded)
    precondition(model.canReuseCloudConversation(decoded))
    precondition(model.recordReference(for: .meeting(person.id)) == nil)

    // Photos/contacts never enter the AI fingerprint. Exportable fields do.
    model.people[0].photoData = Data([8, 9]); model.people[0].contactIdentifier = "another-private-contact"
    precondition(model.recordReference(for: .person(person.id)) == capturedReference && model.isCloudSessionAuthorized(messageID))
    model.people[0].note = "読み取った後に変更"
    precondition(!model.isCloudSessionAuthorized(messageID) && !model.canReuseCloudConversation(captured))
    model.people[0].note = person.note
    precondition(model.isCloudSessionAuthorized(messageID))
    precondition(readPerson(automatic: true).isError)

    // A hidden duplicate must not turn an ambiguous name into a unique match.
    let ambiguous = AgentToolCall(id: "name", name: "read_person", arguments: ["name": person.name])
    let mixed = model.readPersonTool(ambiguous, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(mixed.isError && !mixed.text.contains("別人の非公開メモ") && !mixed.text.contains(person.name))
    let otherGrant = await model.setRecordPrivacy(cloudGrant, target: .person(other.id)); precondition(otherGrant)
    resetMessage()
    let candidates = model.readPersonTool(ambiguous, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(candidates.text.contains(person.id.uuidString) && candidates.text.contains(other.id.uuidString))
    precondition(Set(model.reads) == [.person(person.id), .person(other.id)])
    precondition(model.message.cloudProvenance?.isComplete == true && model.isCloudSessionAuthorized(messageID))

    // Metadata permission cannot grant the related task's content, or vice versa.
    model.tasks = [MemoraTask(id: UUID(), title: "許可前のタスク本文", assignee: person.name, isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id))]
    resetMessage(); precondition(!readPerson().text.contains("許可前のタスク本文"))
    model.tasks[0].privacy = cloudGrant
    resetMessage(); precondition(readPerson().text.contains("許可前のタスク本文"))
    precondition(Set(model.reads) == [.person(person.id), .task(model.tasks[0].id)])
    let withTask = model.message.cloudProvenance!
    let oldPeople = model.people
    model.rejectWrites = true
    precondition(model.addPerson(name: "保存失敗した人物") == nil)
    precondition(!model.setPersonPhoto(person.id, data: Data([99])))
    let failedGrant = await model.setRecordPrivacy(RecordPrivacy(classification: .personal), target: .person(person.id))
    precondition(!failedGrant && model.people == oldPeople && model.isCloudSessionAuthorized(messageID))
    model.rejectWrites = false
    precondition(model.updatePerson(person.id, name: person.name, note: "編集した人物メモ"))
    precondition(!model.people[0].privacy.allowsCloudAI && !model.isCloudSessionAuthorized(messageID) && !model.canReuseCloudConversation(withTask))
    let regranted = await model.setRecordPrivacy(cloudGrant, target: .person(person.id)); precondition(regranted)
    precondition(!model.canReuseCloudConversation(withTask))
    resetMessage(); _ = readPerson()
    precondition(model.isCloudSessionAuthorized(messageID))
    precondition(model.updatePerson(person.id, name: "田中 次郎", note: model.people[0].note))
    precondition(model.tasks[0].assignee == "田中 次郎" && model.tasks[0].privacy?.allowsCloudAI == false)
    precondition(!model.isCloudSessionAuthorized(messageID))

    let automaticGrant = RecordPrivacy(classification: .personal, allowsCloudAI: true, allowsAutomaticAgentAccess: true)
    let allowedAuto = await model.setRecordPrivacy(automaticGrant, target: .person(person.id)); precondition(allowedAuto)
    resetMessage(); precondition(!readPerson(automatic: true).isError)
    let beforeRevoke = model.residentAccessRevision
    let revoked = await model.setRecordPrivacy(RecordPrivacy(classification: .personal), target: .person(person.id)); precondition(revoked)
    precondition(beforeRevoke != model.residentAccessRevision && !model.isCloudSessionAuthorized(messageID))
    model.aiPersonScopeID = person.id
    model.agentPluginPolicies[messageID] = AIPluginExecutionPolicy(pluginIDs: ["person:\(person.id)"], toolIDs: ["memora:read_person", "memora:list_tasks"], recordIDs: [], limitsRecordReads: true, personID: person.id, personTaskIDs: [model.tasks[0].id])
    let scoped = model.automaticRecordTool(.init(id: "list", name: "list_tasks", arguments: [:]), messageID: messageID, purpose: .cloudAI)!
    precondition(scoped.isError)
    model.agentPluginPolicies = [:]

    let reallow = await model.setRecordPrivacy(automaticGrant, target: .person(person.id)); precondition(reallow)
    resetMessage(); _ = readPerson()
    let beforeMerge = model.people
    precondition(model.persistNow(model.tasks, forKey: MemoraModel.StorageKey.tasks))
    var handle: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    precondition(sqlite3_exec(handle, "CREATE TRIGGER fail_tasks BEFORE INSERT ON documents WHEN NEW.key = 'tasks' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.mergePerson(person.id, into: other.id) && model.people == beforeMerge)
    precondition(sqlite3_exec(handle, "DROP TRIGGER fail_tasks;", nil, nil, nil) == SQLITE_OK)
    precondition(model.mergePerson(person.id, into: other.id))
    precondition(model.person(id: person.id) == nil && model.person(id: other.id)?.privacy.allowsCloudAI == false)
    precondition(!model.isCloudSessionAuthorized(messageID) && !model.canReuseCloudConversation(captured))

    let targetGrant = await model.setRecordPrivacy(cloudGrant, target: .person(other.id)); precondition(targetGrant)
    resetMessage(); _ = readPerson(other.id)
    precondition(model.isCloudSessionAuthorized(messageID))
    model.currentTeamID = "another-workspace"
    precondition(model.addPerson(name: "別workspace") == nil && !model.setPersonPhoto(other.id, data: Data([99])))
    precondition(!model.isCloudSessionAuthorized(messageID) && readPerson(other.id).isError)
    let wrongWorkspace = await model.setRecordPrivacy(cloudGrant, target: .person(other.id)); precondition(!wrongWorkspace)
    model.currentTeamID = nil; model.isRestoring = true
    precondition(!model.isCloudSessionAuthorized(messageID) && readPerson(other.id).isError)
    model.isRestoring = false; model.isStoreProtected = true
    precondition(!model.isCloudSessionAuthorized(messageID)); model.isStoreProtected = false
    let reopen = LocalStore(fileURL: storeURL); try reopen.prepare()
    guard case .data(let saved) = reopen.readOutcome(MemoraModel.StorageKey.people) else { preconditionFailure("Missing people") }
    let restored = try JSONDecoder().decode([Person].self, from: saved)
    precondition(restored == model.people)
    let afterRestart = try MemoraModel(storeURL: storeURL); afterRestart.people = restored
    precondition(afterRestart.canReuseCloudConversation(model.message.cloudProvenance))
    precondition(model.deletePerson(other.id))
    precondition(!model.isCloudSessionAuthorized(messageID) && !model.canReuseCloudConversation(model.message.cloudProvenance))
    print("PersonPrivacyChecks: passed (production person codec/privacy/read_person/provenance/authorization + real SQLite; private-by-default, exported fields only, grants/revoke/edit/delete/merge, duplicate identity, related ACLs, typed IDs, legacy/reopen, workspace/protected/restore, atomic failure; isolated fixtures, no API)")
  }
}
