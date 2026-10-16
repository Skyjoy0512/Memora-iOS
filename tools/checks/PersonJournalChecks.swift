import Foundation
import SQLite3

@main struct PersonJournalChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraPersonJournal-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("records.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    let person = Person(id: UUID(), name: "田中 太郎", note: nil, contactIdentifier: nil)
    let other = Person(id: UUID(), name: person.name, note: nil, contactIdentifier: nil)
    model.people = [person, other]
    func add(_ title: String, ids: Set<UUID> = [], kind: LifeLogKind = .memo) -> Bool {
      model.addLifeLogEntry(kind: kind, title: title, summary: "架空のメモ本文", createdAt: .now,
        photoData: nil, eventDate: nil, locationName: nil, personIDs: ids)
    }
    precondition(add("本人の発言とは未確認", ids: [person.id]))
    let linked = model.lifeLogEntries[0]
    precondition(linked.personIDs == [person.id] && linked.privacy.classification == .personal && !linked.privacy.allowsCloudAI)
    precondition(add("同名の別の人物", ids: [other.id]))
    precondition(add("両方の人物を指定", ids: [person.id, other.id]))
    let bothID = model.lifeLogEntries[0].id
    precondition(add("田中太郎さんへの言及"))
    let mention = model.lifeLogEntries[0]
    precondition(Set(model.memory(of: person.id)!.journalEntries.map(\.id)) == [linked.id, bothID])
    precondition(model.memory(of: person.id)?.nameMatchedJournalEntries.isEmpty == true)
    precondition(!add("不明な人物", ids: [UUID()]))
    precondition(!add("位置情報", ids: [person.id], kind: .location))

    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mention)) as! [String: Any]
    legacy.removeValue(forKey: "personIDs")
    let old = try JSONDecoder().decode(LifeLogEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.personIDs.isEmpty && old.title == mention.title)
    legacy["personIDs"] = [person.id.uuidString, person.id.uuidString]
    let deduplicated = try JSONDecoder().decode(LifeLogEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(deduplicated.personIDs == [person.id])
    let beforeEdit = AIRecordFingerprint.make(linked)
    precondition(model.updateLifeLogEntry(linked.id, title: linked.title, summary: "編集した本文", createdAt: linked.createdAt, locationName: nil, place: nil))
    precondition(beforeEdit != AIRecordFingerprint.make(model.lifeLogEntries.first { $0.id == linked.id }!))

    // A relationship never supplies a cloud grant. The production privacy editor enforces its floor.
    let general = RecordPrivacy(classification: .general, allowsCloudAI: true)
    let invalidGrant = await model.setRecordPrivacy(general, target: .journal(linked.id))
    precondition(!invalidGrant)
    let grant = RecordPrivacy(classification: .personal, allowsCloudAI: true, allowsAutomaticAgentAccess: true)
    let validGrant = await model.setRecordPrivacy(grant, target: .journal(linked.id))
    precondition(validGrant)
    let messageID = UUID()
    model.aiPersonScopeID = person.id
    let policy = AIPluginExecutionPolicy(pluginIDs: ["person:\(person.id)"],
      toolIDs: ["memora:read_record", "memora:search_records", "memora:read_person"], recordIDs: [],
      limitsRecordReads: true, personID: person.id, personJournalIDs: [linked.id])
    model.agentPluginPolicies[messageID] = policy
    precondition(model.personPolicyIsCurrent(policy))
    precondition(policy.permits("read_record", arguments: ["id": linked.id.uuidString]))
    precondition(!policy.permits("read_record", arguments: ["id": mention.id.uuidString]))
    let personCall = AgentToolCall(id: "person", name: "read_person", arguments: ["person_id": person.id.uuidString])
    let read = model.readPersonTool(personCall, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(read.text.contains("編集した本文") && read.text.contains("本人の発言・参加の確定ではない"))
    precondition(!read.text.contains("同名の別の人物") && !read.text.contains(mention.title))
    precondition(model.reads == [.journal(linked.id)])
    let deniedGrant = await model.setRecordPrivacy(RecordPrivacy(classification: .personal), target: .journal(linked.id))
    precondition(deniedGrant)
    let revokedRead = model.readPersonTool(personCall, messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(!revokedRead.text.contains("編集した本文") && model.reads.isEmpty)
    let restoredGrant = await model.setRecordPrivacy(grant, target: .journal(linked.id)); precondition(restoredGrant)

    // Colliding UUIDs from a different record type must not broaden a person grant.
    model.meetings = [Meeting(id: linked.id, title: "他人の会議の秘密", participantIDs: [other.id], privacy: general)]
    let recordCall = AgentToolCall(id: "record", name: "read_record", arguments: ["id": linked.id.uuidString])
    let record = model.automaticRecordTool(recordCall, messageID: messageID, purpose: .cloudAI)!
    precondition(record.text.contains("編集した本文") && !record.text.contains("他人の会議の秘密"))
    precondition(model.reads == [.journal(linked.id)] && model.message.sources.isEmpty)
    let search = model.automaticRecordTool(.init(id: "search", name: "search_records", arguments: ["query": ""]), messageID: messageID, purpose: .cloudAI)!
    precondition(search.text.contains(linked.title) && !search.text.contains(mention.title) && !search.text.contains("他人の会議の秘密"))
    let denied = model.automaticRecordTool(.init(id: "denied", name: "read_record", arguments: ["id": mention.id.uuidString]), messageID: messageID, purpose: .cloudAI)!
    precondition(denied.isError)
    // A meeting grant with the same UUID likewise cannot expose the journal.
    model.meetings[0].participantIDs = [person.id]
    var meetingOnly = policy; meetingOnly.recordIDs = [linked.id]; meetingOnly.personJournalIDs = []
    model.agentPluginPolicies[messageID] = meetingOnly
    let meetingRead = model.automaticRecordTool(recordCall, messageID: messageID, purpose: .cloudAI)!
    precondition(meetingRead.text.contains("他人の会議の秘密") && !meetingRead.text.contains("編集した本文"))
    precondition(model.reads == [.meeting(linked.id)])
    model.agentPluginPolicies[messageID] = policy
    model.meetings[0].participantIDs = [other.id]
    model.currentTeamID = "another-workspace"
    precondition(model.automaticRecordTool(recordCall, messageID: messageID, purpose: .cloudAI)!.isError)
    precondition(!add("別ワークスペース", ids: [person.id]))
    model.currentTeamID = nil

    // Location, automatic origin, missing parents and a private parent still refuse reads.
    for (kind, origin) in [(LifeLogKind.location, LifeLogOrigin.manual), (.memo, .visit)] {
      var restricted = linked; restricted.id = UUID(); restricted.kind = kind; restricted.origin = origin; restricted.privacy = grant
      model.lifeLogEntries.append(restricted)
      precondition(!model.allowsJournalAccess(restricted, purpose: .cloudAI))
    }
    var orphan = linked; orphan.meetingID = UUID(); orphan.privacy = grant
    precondition(!model.allowsJournalAccess(orphan, purpose: .cloudAI))
    var underclassified = linked; underclassified.privacy = general
    precondition(!model.allowsJournalAccess(underclassified, purpose: .cloudAI))
    var manualOnly = linked; manualOnly.privacy = RecordPrivacy(classification: .personal, allowsCloudAI: true)
    precondition(model.allowsJournalAccess(manualOnly, purpose: .cloudAI) && !model.allowsJournalAccess(manualOnly, purpose: .automaticAgent))
    var privateParent = model.meetings[0]; privateParent.privacy = RecordPrivacy(classification: .sensitive)
    model.meetings = [privateParent]; orphan.meetingID = privateParent.id
    precondition(!model.allowsJournalAccess(orphan, purpose: .cloudAI))

    let originalEntries = model.lifeLogEntries
    model.rejectWrites = true
    precondition(!model.updateLifeLogEntry(linked.id, title: "失敗する編集", summary: "", createdAt: .now, locationName: nil, place: nil, personIDs: [other.id]))
    precondition(model.lifeLogEntries == originalEntries)
    model.rejectWrites = false
    precondition(model.updateLifeLogEntry(linked.id, title: linked.title, summary: "編集した本文", createdAt: linked.createdAt, locationName: nil, place: nil, personIDs: [other.id]))
    let reassigned = model.lifeLogEntries.first { $0.id == linked.id }!
    precondition(!reassigned.privacy.allowsCloudAI && !reassigned.privacy.allowsAutomaticAgentAccess)
    precondition(!model.personPolicyIsCurrent(policy))
    precondition(model.readPersonTool(personCall, messageID: messageID, compact: false, purpose: .cloudAI).isError)
    precondition(model.automaticRecordTool(recordCall, messageID: messageID, purpose: .cloudAI)!.isError)

    // Failing the last write rolls back people, tasks, meeting tags AND journal links.
    model.tasks = [MemoraTask(id: UUID(), title: "統合する担当タスク", assignee: other.name, isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: other.id))]
    precondition(model.persistBatch { [("people", try RecordStore.encoded(model.people)), ("tasks", try RecordStore.encoded(model.tasks)),
      ("meetings", try RecordStore.encoded(model.meetings)), ("journal", try RecordStore.encoded(model.lifeLogEntries))] })
    let oldPeople = model.people, oldTasks = model.tasks, oldMeetings = model.meetings, oldEntries = model.lifeLogEntries
    let keys = ["people", "tasks", "meetings", "journal"]
    let oldStored = keys.map { PersonTaskChecksRead.read(model.store, $0) }
    var handle: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    precondition(sqlite3_exec(handle, "CREATE TRIGGER fail_journal BEFORE INSERT ON documents WHEN NEW.key = 'journal' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.mergePerson(other.id, into: person.id))
    precondition(model.people == oldPeople && model.tasks == oldTasks && model.meetings == oldMeetings && model.lifeLogEntries == oldEntries)
    precondition(keys.map { PersonTaskChecksRead.read(model.store, $0) } == oldStored)
    precondition(sqlite3_exec(handle, "DROP TRIGGER fail_journal;", nil, nil, nil) == SQLITE_OK)
    precondition(model.mergePerson(other.id, into: person.id))
    precondition(model.tasks[0].relationships.assigneePersonID == person.id)
    precondition(model.lifeLogEntries.first { $0.id == linked.id }?.personIDs == [person.id])
    precondition(model.lifeLogEntries.first { $0.id == bothID }?.personIDs == [person.id])
    precondition(model.memory(of: person.id)?.nameMatchedJournalEntries.map(\.id) == [mention.id])
    let active = model.lifeLogEntries.first { $0.id == linked.id }!
    let grantAgain = await model.setRecordPrivacy(grant, target: .journal(active.id)); precondition(grantAgain)
    model.agentPluginPolicies[messageID] = policy
    model.deleteLifeLogEntry(active.id)
    precondition(!model.personPolicyIsCurrent(policy))
    model.restoreTrashedLifeLogEntry(active.id)
    precondition(model.lifeLogEntries.first { $0.id == active.id }?.personIDs == [person.id])
    precondition(model.updateLifeLogEntry(active.id, title: active.title, summary: active.summary, createdAt: active.createdAt, locationName: nil, place: nil, personIDs: []))
    precondition(model.lifeLogEntries.first { $0.id == active.id }?.privacy.allowsCloudAI == false)
    precondition(!model.personPolicyIsCurrent(policy))

    let tombstone = model.lifeLogEntries.first { !$0.personIDs.isEmpty }!
    precondition(model.deletePerson(person.id))
    let replacement = Person(id: UUID(), name: person.name, note: nil, contactIdentifier: nil); model.people = [replacement]
    precondition(model.memory(of: replacement.id)?.journalEntries.isEmpty == true)
    precondition(model.memory(of: replacement.id)?.nameMatchedJournalEntries.contains { $0.id == tombstone.id } == false)
    precondition(model.updateLifeLogEntry(tombstone.id, title: tombstone.title, summary: "別の編集", createdAt: tombstone.createdAt, locationName: nil, place: nil))
    precondition(model.lifeLogEntries.first { $0.id == tombstone.id }?.personIDs == tombstone.personIDs)
    model.isRestoring = true; precondition(!add("復元中", ids: [replacement.id])); model.isRestoring = false
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    let restored = try JSONDecoder().decode([LifeLogEntry].self, from: PersonTaskChecksRead.read(reopened, "journal"))
    precondition(restored == model.lifeLogEntries)
    print("PersonJournalChecks: passed (production journal codec/mutations, person scope/read/search, privacy editor + real SQLite; legacy, same-name IDs, tombstones, grants, parent restrictions, revoke/edit/delete, typed UUID collision, merge rollback, reopen; isolated fixtures only)")
  }
}

private enum PersonTaskChecksRead {
  static func read(_ store: LocalStore, _ key: String) -> Data {
    guard case .data(let bytes) = store.readOutcome(key) else { preconditionFailure("Missing fixture key") }; return bytes
  }
}
