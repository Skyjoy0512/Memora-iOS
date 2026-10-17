import Foundation
import SQLite3

@main struct MemoryEditingChecks {
  @MainActor static func main() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("memory.sqlite")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    let model = MemoraModel(store: store)
    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let now = oldDate.addingTimeInterval(100)
    func memory(_ text: String, workspace: String? = nil, subject: String = "user", predicate: String = "役割",
                status: AIMemory.Status = .current) -> AIMemory {
      .init(id: UUID(), text: text, origin: .told, createdAt: oldDate,
        semantic: .init(type: .role, subjectID: subject, predicate: predicate, value: text, sourceReference: "conversation:\(UUID())",
          observedAt: oldDate, updatedAt: oldDate, validFrom: oldDate, status: status, workspaceID: workspace))
    }
    let old = memory("営業担当")
    let proposed = memory("管理職", status: .conflicted)
    let foreign = memory("別ワークスペース", workspace: "team")
    let otherPerson = memory("別の人物", subject: UUID().uuidString)
    let note = memory("一般メモ", predicate: "note")
    let disabled = memory("無効化した役割", status: .disabled)
    let historical = memory("過去の役割", status: .historical)
    let seed = [proposed, old, foreign, otherPerson, note, disabled, historical]
    precondition(model.storeAIMemories(seed))
    var draft = AIMemoryEditDraft(memory: proposed)
    draft.status = .current
    let related = AIMemoryEditPlan.relatedMemories(in: seed, to: proposed, predicate: draft.predicate)
    precondition(related == [old])
    let normal = draft.plan(for: proposed, related: related, now: now)
    precondition(model.saveAIMemoryEdit(normal))
    precondition(model.aiMemories[0].status == .conflicted && model.aiMemories[1].status == .conflicted)
    precondition(model.aiMemories[1].revisions?.last?.semantic == old.semantic)
    precondition(model.aiMemories[1].updatedAt == now)
    precondition(!model.saveAIMemoryEdit(normal)) // A settled edit is not replayable.
    precondition(model.storeAIMemories(seed))
    draft.resolvesConflicts = true
    let plan = draft.plan(for: proposed, related: related, now: now)
    let beforeFingerprint = AIRecordFingerprint.make(seed)
    precondition(model.saveAIMemoryEdit(plan))
    let resolved = model.aiMemories
    precondition(resolved[0].status == .current && resolved[0].canUse(workspaceID: nil, now: now))
    precondition(resolved[1].status == .historical && !resolved[1].canUse(workspaceID: nil, now: now))
    precondition(resolved[1].semantic?.validFrom == oldDate && resolved[1].semantic?.validTo == now)
    precondition(resolved[1].semantic?.sourceReference == old.semantic?.sourceReference)
    precondition(resolved[1].revisions?.last?.semantic == old.semantic && resolved[0].revisions?.last?.semantic == proposed.semantic)
    precondition(resolved.dropFirst(2).elementsEqual(seed.dropFirst(2)))
    precondition(AIRecordFingerprint.make(resolved) != beforeFingerprint)
    let reopened = LocalStore(fileURL: url); try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome(StorageKey.aiMemories) else { preconditionFailure("missing persisted memories") }
    let persisted = try JSONDecoder().decode([AIMemory].self, from: data)
    precondition(persisted == resolved)

    func rejects(_ mutation: () -> Void) {
      precondition(model.storeAIMemories(seed))
      mutation()
      let unchanged = model.aiMemories
      precondition(!model.saveAIMemoryEdit(plan))
      precondition(model.aiMemories == unchanged)
      model.currentTeamID = nil; model.isRestoring = false; model.isStoreProtected = false
    }
    rejects { model.aiMemories[0].text = "他の編集" }
    rejects { model.aiMemories.removeFirst() }
    rejects { model.aiMemories[1].semantic?.sensitivity = .sensitive }
    rejects { model.aiMemories.remove(at: 1) }
    rejects { model.aiMemories.append(memory("新たな候補", status: .updateCandidate)) }
    rejects { model.currentTeamID = "team" }
    rejects { model.isRestoring = true }
    rejects { model.isStoreProtected = true }
    precondition(model.storeAIMemories(seed))
    var badPlan = plan; badPlan.related = []
    precondition(!model.saveAIMemoryEdit(badPlan))
    badPlan = plan; badPlan.related.append(old)
    precondition(!model.saveAIMemoryEdit(badPlan))
    badPlan = plan; badPlan.replacement.semantic?.subjectID = "another"
    precondition(!model.saveAIMemoryEdit(badPlan))
    badPlan = plan; badPlan.replacement.semantic?.workspaceID = "team"
    precondition(!model.saveAIMemoryEdit(badPlan))
    var longDraft = draft; longDraft.text = String(repeating: "文", count: 201)
    precondition(!model.saveAIMemoryEdit(longDraft.plan(for: proposed, related: related)))
    longDraft.text = "   "
    precondition(!model.saveAIMemoryEdit(longDraft.plan(for: proposed, related: related)))
    var duplicate = seed; duplicate.append(old)
    precondition(plan.applying(to: duplicate, workspaceID: nil) == nil)
    let legacy = AIMemory(id: UUID(), text: "以前の形式", origin: .told, createdAt: oldDate)
    var legacyDraft = AIMemoryEditDraft(memory: legacy); legacyDraft.text = "改訂した内容"
    let legacyPlan = legacyDraft.plan(for: legacy, related: [], now: now)
    precondition(legacyPlan.applying(to: [legacy], workspaceID: nil)?.first?.revisions?.first?.semantic == nil)
    precondition(AIMemoryEditPlan.relatedMemories(in: [note, memory("別の一般メモ", predicate: "note")], to: note, predicate: "note").isEmpty)
    var sensitiveDraft = draft; sensitiveDraft.sensitivity = .sensitive
    let sensitiveResult = sensitiveDraft.plan(for: proposed, related: related, now: now).applying(to: seed, workspaceID: nil)!
    precondition(!sensitiveResult[0].canUse(workspaceID: nil, now: now))

    // A real SQLite failure must retain every peer and the published in-memory state.
    precondition(model.storeAIMemories(seed))
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_memory BEFORE INSERT ON documents WHEN NEW.key = 'memories' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.saveAIMemoryEdit(plan) && model.aiMemories == seed)
    guard case .data(let failedData) = store.readOutcome(StorageKey.aiMemories) else { preconditionFailure("missing old document") }
    let afterFailure = try JSONDecoder().decode([AIMemory].self, from: failedData)
    precondition(afterFailure == seed)
    precondition(!model.deleteAIMemory(proposed) && !model.deleteAllAIMemories(in: nil))
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_memory", nil, nil, nil) == SQLITE_OK)
    precondition(model.saveAIMemoryEdit(plan))
    precondition(!model.deleteAIMemory(proposed)) // Old editor cannot delete the updated value.
    precondition(model.deleteAIMemory(model.aiMemories[0]))
    model.currentTeamID = "team"
    precondition(!model.deleteAllAIMemories(in: nil))
    precondition(model.deleteAllAIMemories(in: "team"))
    precondition(model.aiMemories.allSatisfy { $0.workspaceID == nil })
    print("MemoryEditingChecks: passed (production edit plan/management, explicit resolution, history, stale values, scope, sensitivity, legacy, SQLite reopen and atomic failure; no AI calls)")
  }

}

@MainActor final class MemoraModel {
  var store: LocalStore
  var aiMemories: [AIMemory] = []
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  init(store: LocalStore) { self.store = store }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    do { try store.write(key, data: JSONEncoder().encode(value)); return true } catch { return false }
  }
}

enum StorageKey { static let aiMemories = "memories" }
