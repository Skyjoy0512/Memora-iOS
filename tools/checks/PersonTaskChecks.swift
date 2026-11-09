import Foundation
import SQLite3

@main
struct PersonTaskChecks {
  @MainActor static func main() throws {
    try readOnlyMutationChecks()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("MemoraPersonTasks-\(UUID())")
    defer { try? fm.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("records.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    var first = Person(id: UUID(), name: "田中 太郎", note: "営業", contactIdentifier: nil)
    let other = Person(id: UUID(), name: "田中 太郎", note: "開発", contactIdentifier: nil)
    first.privacy = RecordPrivacy(classification: .personal, allowsCloudAI: true)
    model.people = [first, other]
    let options = PersonSelectionOption.options(model.people)
    precondition(Set(options.map(\.label)).count == 2 && options.allSatisfy { $0.label.contains($0.id.uuidString.prefix(8)) })
    let collisionA = Person(id: UUID(uuidString: "12345678-0000-4000-8000-000000000001")!, name: first.name, note: nil, contactIdentifier: nil)
    let collisionB = Person(id: UUID(uuidString: "12345678-0000-4000-8000-000000000002")!, name: first.name, note: nil, contactIdentifier: nil)
    precondition(Set(PersonSelectionOption.options([collisionA, collisionB]).map(\.label)).count == 2)
    let emptyRelationships = try JSONDecoder().decode(TaskRelationships.self, from: Data("{}".utf8))
    precondition(emptyRelationships.documentIDs.isEmpty && emptyRelationships.assigneePersonID == nil)
    let legacy = MemoraTask(id: UUID(), title: "名前のみ", assignee: "田中太郎さん", isCompleted: false)
    precondition(!PersonTaskAssociation.nameMatches(legacy, normalizedName: PersonIdentity.normalized(first.name), isUnique: false))
    precondition(PersonTaskAssociation.nameMatches(legacy, normalizedName: PersonIdentity.normalized(first.name), isUnique: true))
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
    legacyJSON["relationships"] = ["documentIDs": []]
    let decoded = try JSONDecoder().decode(MemoraTask.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
    precondition(decoded.relationships.assigneePersonID == nil && decoded.assignee == legacy.assignee)

    precondition(model.addTask(title: "IDで担当", assignee: "別の表記", dueDate: nil, ownedByMe: false, assigneePersonID: first.id))
    let assigned = model.tasks[0]
    precondition(assigned.relationships.assigneePersonID == first.id && assigned.assignee == first.name)
    precondition(!TaskOwnership.isMine(assigned, names: [first.name]))
    precondition(assigned.privacy?.classification == .personal && assigned.privacy?.allowsCloudAI == false)
    let count = model.tasks.count
    precondition(!model.addTask(title: "不明なID", assignee: first.name, dueDate: nil, assigneePersonID: UUID()))
    precondition(!model.addTask(title: "自分と別担当の矛盾", assignee: first.name, dueDate: nil, ownedByMe: true, assigneePersonID: first.id))
    precondition(model.tasks.count == count)
    precondition(model.addTask(title: "旧形式を保持", assignee: first.name, dueDate: nil, ownedByMe: false))
    let unboundID = model.tasks[0].id
    precondition(model.tasks[0].relationships.assigneePersonID == nil)
    model.tasks.append(MemoraTask(id: UUID(), title: "他方の担当", assignee: other.name, isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: other.id)))
    precondition(model.memory(of: first.id)?.assignedTasks.map(\.id) == [assigned.id])
    precondition(model.memory(of: other.id)?.assignedTasks.count == 1)
    precondition(model.memory(of: first.id)?.nameMatchedTasks.isEmpty == true)

    // Both reads and the next model send use this same production scope check.
    model.aiPersonScopeID = first.id
    let messageID = UUID()
    let policy = AIPluginExecutionPolicy(pluginIDs: ["person:\(first.id)"], toolIDs: ["memora:read_person", "memora:list_tasks"], recordIDs: [], limitsRecordReads: true, personID: first.id, personTaskIDs: [assigned.id])
    model.agentPluginPolicies[messageID] = policy
    precondition(model.personPolicyIsCurrent(policy))
    precondition(policy.includesTask(id: assigned.id, meetingID: nil))
    precondition(!policy.includesTask(id: unboundID, meetingID: nil))
    precondition(!policy.permits("read_person", arguments: ["name": "", "person_id": other.id.uuidString]))
    let call = AgentToolCall(id: "read", name: "read_person", arguments: ["name": "", "person_id": first.id.uuidString])
    let nameOnly = AgentToolCall(id: "name-only", name: "read_person", arguments: ["name": first.name])
    precondition(model.readPersonTool(nameOnly, messageID: messageID, compact: false, purpose: .cloudAI).isError)
    let privateRead = model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(!privateRead.text.contains(assigned.title) && model.reads == [.person(first.id)])
    var granted = assigned
    granted.privacy = RecordPrivacy(classification: .personal, allowsCloudAI: true, allowsAutomaticAgentAccess: true)
    model.tasks[model.tasks.firstIndex { $0.id == assigned.id }!] = granted
    let allowedRead = model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(allowedRead.text.contains(assigned.title) && !allowedRead.text.contains("他方の担当"))
    precondition(Set(model.reads) == [.person(first.id), .task(assigned.id)])
    let wrong = AgentToolCall(id: "wrong", name: "read_person", arguments: ["name": "", "person_id": other.id.uuidString])
    precondition(model.readPersonTool(wrong, messageID: messageID, compact: false, purpose: .cloudAI).isError)

    let beforeReassign = model.tasks
    model.rejectWrites = true
    precondition(!model.updateTask(assigned.id, title: assigned.title, assignee: other.name, dueDate: nil, meetingID: nil, workDate: nil,
      ownedByMe: false, relationships: TaskRelationships(assigneePersonID: other.id)))
    precondition(model.tasks == beforeReassign)
    model.rejectWrites = false
    precondition(model.updateTask(assigned.id, title: assigned.title, assignee: other.name, dueDate: nil, meetingID: nil, workDate: nil,
      ownedByMe: false, relationships: TaskRelationships(assigneePersonID: other.id)))
    let changed = model.tasks.first { $0.id == assigned.id }!
    precondition(changed.relationships.assigneePersonID == other.id && changed.privacy?.allowsCloudAI == false && changed.privacy?.allowsAutomaticAgentAccess == false)
    precondition(!model.personPolicyIsCurrent(policy))
    precondition(model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI).isError)

    // A privacy floor inherited from an old meeting survives detachment and reassignment.
    let secret = Meeting(title: "非公開", participantIDs: [other.id], privacy: RecordPrivacy(classification: .sensitive))
    model.meetings = [secret]
    var inherited = changed; inherited.meetingID = secret.id; inherited.privacy = nil
    model.tasks[model.tasks.firstIndex { $0.id == assigned.id }!] = inherited
    precondition(model.updateTask(assigned.id, title: assigned.title, assignee: first.name, dueDate: nil, meetingID: nil, workDate: nil,
      ownedByMe: false, relationships: TaskRelationships(assigneePersonID: first.id)))
    precondition(model.task(id: assigned.id)?.privacy?.classification == .sensitive)
    precondition(model.task(id: assigned.id)?.privacy?.allowsCloudAI == false)

    // Failing the second SQLite write must not rename the person in memory or on disk.
    precondition(model.persistBatch { [(MemoraModel.StorageKey.people, try RecordStore.encoded(model.people)),
      (MemoraModel.StorageKey.tasks, try RecordStore.encoded(model.tasks)), (MemoraModel.StorageKey.meetings, try RecordStore.encoded(model.meetings))] })
    var handle: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    let oldPeople = model.people, oldTasks = model.tasks, oldMeetings = model.meetings
    let oldStoredPeople = read(model.store, "people")
    precondition(sqlite3_exec(handle, "CREATE TRIGGER fail_fixture BEFORE INSERT ON documents WHEN NEW.key = 'tasks' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.updatePerson(first.id, name: "改名", note: "編集内容"))
    precondition(!model.mergePerson(first.id, into: other.id))
    precondition(model.people == oldPeople && model.tasks == oldTasks && model.meetings == oldMeetings)
    precondition(read(model.store, "people") == oldStoredPeople)
    precondition(sqlite3_exec(handle, "DROP TRIGGER fail_fixture;", nil, nil, nil) == SQLITE_OK)
    precondition(model.updatePerson(first.id, name: "田中 一郎", note: first.note))
    precondition(model.task(id: assigned.id)?.assignee == "田中 一郎")
    precondition(model.task(id: unboundID)?.assignee == first.name && model.task(id: unboundID)?.relationships.assigneePersonID == nil)
    precondition(model.memory(of: other.id)?.nameMatchedTasks.contains { $0.id == unboundID } == true)
    precondition(model.mergePerson(first.id, into: other.id))
    precondition(model.task(id: assigned.id)?.relationships.assigneePersonID == other.id)
    precondition(model.task(id: unboundID)?.relationships.assigneePersonID == nil)
    precondition(model.people.count == 1 && model.meetings[0].participantIDs == [other.id])

    // Deleting a person retains task tombstones instead of transferring them by name.
    model.rejectWrites = true
    precondition(!model.deletePerson(other.id) && model.people.count == 1)
    model.rejectWrites = false
    precondition(model.deletePerson(other.id))
    let replacement = Person(id: UUID(), name: other.name, note: nil, contactIdentifier: nil)
    model.people = [replacement]
    precondition(model.memory(of: replacement.id)?.assignedTasks.isEmpty == true)
    precondition(model.memory(of: replacement.id)?.nameMatchedTasks.contains { $0.id == assigned.id } == false)
    precondition(model.task(id: assigned.id)?.relationships.assigneePersonID == other.id)
    // Preserve a tombstone on unrelated edits; reject guessed, newly introduced IDs.
    precondition(model.updateTask(assigned.id, title: "編集", assignee: other.name, dueDate: nil, meetingID: nil, workDate: nil,
      relationships: model.task(id: assigned.id)!.relationships))
    precondition(!model.updateTask(assigned.id, title: "編集", assignee: other.name, dueDate: nil, meetingID: nil, workDate: nil,
      relationships: TaskRelationships(assigneePersonID: UUID())))
    model.currentTeamID = "other-workspace"
    precondition(!model.updatePerson(replacement.id, name: "変更", note: nil))
    precondition(model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI).isError)
    model.currentTeamID = nil; model.isRestoring = true
    precondition(!model.addTask(title: "復元中", assignee: "", dueDate: nil))
    model.isRestoring = false
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    let reloaded = try JSONDecoder().decode([MemoraTask].self, from: read(reopened, "tasks"))
    precondition(reloaded.first { $0.id == assigned.id }?.relationships.assigneePersonID == other.id)
    let bulk = try MemoraModel(storeURL: root.appendingPathComponent("bulk.sqlite"))
    bulk.people = (0..<500).map { Person(id: UUID(), name: "人物\($0)", note: nil, contactIdentifier: nil) }
    let focus = bulk.people[0]
    bulk.tasks = (0..<2_000).map { MemoraTask(id: UUID(), title: "タスク\($0)", assignee: focus.name, isCompleted: false) }
    let started = Date()
    let related = bulk.memory(of: focus.id)
    precondition(related?.nameMatchedTasks.count == 2_000 && related?.assignedTasks.isEmpty == true)
    print("PersonTaskChecks host lookup: 500 people, 2000 tasks, \(Date().timeIntervalSince(started))s (not physical-device performance)")
    print("PersonTaskChecks: passed (production task/people/scope/read_person + real SQLite; same-name IDs, legacy unconfirmed, privacy/revoke, reassignment, rename/merge rollback, tombstones, workspace, reopen; isolated fixtures only)")
  }

  @MainActor static func readOnlyMutationChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraReadOnlyTasks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try MemoraModel(storeURL: root.appendingPathComponent("store.sqlite"))
    precondition(model.addTask(title: "保持する課題", assignee: "", dueDate: nil))
    let original = model.tasks
    let id = original[0].id
    guard case .data(let saved) = model.store.readOutcome("tasks") else { preconditionFailure() }
    for mode in 0..<3 {
      model.currentTeamID = mode == 0 ? "read-only-team" : nil
      model.isRestoring = mode == 1
      model.isStoreProtected = mode == 2
      model.toggleTask(id)
      model.setTaskDueDate(id, to: .now)
      model.setTaskWorkDate(id, to: .now)
      precondition(!model.deleteTask(id))
      precondition(!model.updateTask(id, title: "拒否する編集", assignee: "", dueDate: nil, meetingID: nil, workDate: nil))
      precondition(!model.addTask(title: "拒否する追加", assignee: "", dueDate: nil))
      var added = original[0]; added.id = UUID()
      precondition(!model.insertTasks([added]))
      precondition(model.tasks == original)
      guard case .data(let retained) = model.store.readOutcome("tasks") else { preconditionFailure() }
      precondition(retained == saved)
    }
    model.currentTeamID = nil; model.isRestoring = false; model.isStoreProtected = false
    model.toggleTask(id)
    precondition(model.tasks[0].isCompleted)
    print("PASS: actual task mutators refuse team/restore/protected writes with SQLite bytes unchanged; personal edits remain available")
  }

  static func read(_ store: LocalStore, _ key: String) -> Data {
    guard case .data(let bytes) = store.readOutcome(key) else { preconditionFailure("Missing fixture key") }; return bytes
  }
}
