import Foundation

@main struct MemoryRetrievalChecks {
  static func main() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let legacy = AIMemory(id: UUID(), text: "短い文章を好む", origin: .told, createdAt: date)
    let decoded = try JSONDecoder().decode(AIMemory.self, from: JSONEncoder().encode(legacy))
    precondition(decoded.canUse(workspaceID: nil) && !decoded.canUse(workspaceID: "business"))
    var value = legacy
    value.semantic = .init(value: legacy.text, sourceReference: "fixture", observedAt: date, updatedAt: date, validFrom: date)
    for status in AIMemory.Status.allCases {
      value.semantic?.status = status
      precondition(value.canUse(workspaceID: nil) == (status == .current))
    }
    value.semantic?.status = .current
    value.semantic?.sensitivity = .sensitive
    precondition(!value.canUse(workspaceID: nil))
    value.semantic?.sensitivity = .standard
    value.semantic?.validTo = date
    precondition(!value.canUse(workspaceID: nil))
    let oldFact = legacy.edited(text: "営業担当", status: .current, kind: .role, sensitivity: .standard, predicate: "役割", workspaceID: nil)
    var newFact = AIMemory(id: UUID(), text: "管理職", origin: .told, createdAt: date)
    newFact = newFact.edited(text: "管理職", status: .current, kind: .role, sensitivity: .standard, predicate: "役割", workspaceID: nil)
    let conflicts = AIMemory.reconciling([oldFact, newFact], editedID: newFact.id)
    precondition(conflicts.allSatisfy { $0.status == .conflicted && !$0.canUse(workspaceID: nil) })
    precondition(oldFact.revisions?.first?.text == legacy.text)
    var repeated = oldFact
    for index in 0..<40 { repeated = repeated.edited(text: "改訂\(index)", status: .current, kind: .fact, sensitivity: .standard, predicate: "note", workspaceID: nil) }
    precondition(repeated.revisions?.count == 30)
    let wanted = MemoryRetrievalItem(id: UUID(), kind: .episode, text: "田中さんと新規事業の提案書の構成を検討した", updatedAt: date, sourceID: UUID())
    let other = MemoryRetrievalItem(id: UUID(), kind: .episode, text: "旅行の宿泊先を相談", updatedAt: date, workspaceID: "other", sourceID: UUID())
    let sameName = MemoryRetrievalItem(id: UUID(), kind: .episode, text: wanted.text, updatedAt: date, personID: UUID(), sourceID: UUID())
    let found = try MemoryRetrievalOrchestrator.retrieve("以前の新規事業の提案書について", candidates: [other, sameName, wanted], workspaceID: nil, personID: nil)
    precondition(found.first?.item.id == wanted.id && found.count == 1)
    let empty = try MemoryRetrievalOrchestrator.retrieve("宇宙探査の予算", candidates: [wanted], workspaceID: nil, personID: nil)
    precondition(empty.isEmpty)
    let deleted = try MemoryRetrievalOrchestrator.retrieve("新規事業", candidates: [], workspaceID: nil, personID: nil)
    precondition(deleted.isEmpty)
    try checkCache(wanted: wanted, other: other, sameName: sameName)
    let bulk = (0..<2_000).map { index in MemoryRetrievalItem(id: UUID(), kind: .episode, text: "会議番号\(index) 開発計画の進捗確認", updatedAt: date, sourceID: UUID()) }
    let start = Date()
    let large = try MemoryRetrievalOrchestrator.retrieve("開発計画の進捗", candidates: bulk, workspaceID: nil, personID: nil)
    precondition(large.count <= 5)
    print("MemoryRetrievalChecks: passed (legacy, validity, conflict states, sensitivity, Japanese FTS5, scope, snapshot invalidation, eviction, expiry, concurrent reads, 2000 items \(Date().timeIntervalSince(start))s; no LLM quality claim)")
  }

  private static func checkCache(wanted: MemoryRetrievalItem, other: MemoryRetrievalItem, sameName: MemoryRetrievalItem) throws {
    typealias Retrieval = MemoryRetrievalOrchestrator
    Retrieval.invalidate()
    func search(_ items: [MemoryRetrievalItem], workspace: String? = nil, person: UUID? = nil, query: String = "新規事業 提案書") throws -> [Retrieval.Hit] {
      try Retrieval.retrieve(query, candidates: items, workspaceID: workspace, personID: person)
    }
    func expect(_ condition: @autoclosure () throws -> Bool) rethrows {
      let result = try condition()
      precondition(result)
    }
    let before = Retrieval.cacheChecks
    _ = try search([wanted])
    _ = try search([wanted], query: "提案書 構成")
    precondition(Retrieval.cacheChecks.builds == before.builds + 1 && Retrieval.cacheChecks.reuses == before.reuses + 1)
    var semantic = wanted
    semantic.kind = .semantic
    _ = try search([semantic])
    _ = try search([wanted])
    precondition(Retrieval.cacheChecks.entries == 2 && Retrieval.cacheChecks.builds == before.builds + 2)
    Retrieval.invalidate(kind: .episode)
    precondition(Retrieval.cacheChecks.entries == 1)
    let historyChangeBuilds = Retrieval.cacheChecks.builds
    _ = try search([semantic])
    precondition(Retrieval.cacheChecks.builds == historyChangeBuilds)
    // Matching IDs alone must not preserve old text, date, kind, order or source.
    var edited = wanted
    edited.text = "旅行の宿泊先を相談"
    try expect(try search([edited]).isEmpty)
    try expect(try search([wanted]).first?.item == wanted)
    edited = wanted
    edited.sourceID = UUID()
    edited.updatedAt = wanted.updatedAt.addingTimeInterval(10)
    try expect(try search([edited]).first?.item == edited)
    let priorOrderBuilds = Retrieval.cacheChecks.builds
    _ = try search([wanted, edited])
    _ = try search([edited, wanted])
    precondition(Retrieval.cacheChecks.builds == priorOrderBuilds + 2)
    // Mixed-kind snapshots cannot grow the cache beyond two slots.
    _ = try search([wanted, semantic])
    precondition(Retrieval.cacheChecks.entries <= 2 && Retrieval.cacheChecks.estimatedBytes <= 16 * 1_024 * 1_024)
    _ = try search([other], workspace: "other")
    precondition(Retrieval.cacheChecks.entries == 1)
    try expect(try search([wanted, other, sameName]).map(\.item) == [wanted])
    try expect(try search([wanted, other, sameName], person: sameName.personID).map(\.item) == [sameName])
    precondition(Retrieval.cacheChecks.entries == 1)
    try expect(try search([]).isEmpty && Retrieval.cacheChecks.entries == 0)
    _ = try search([wanted])
    edited = wanted
    edited.text = "権限変更後のテキスト"
    // Even a non-searchable query must discard a superseded snapshot.
    _ = try search([edited], query: "!")
    precondition(Retrieval.cacheChecks.entries == 0)
    _ = try search([wanted])
    let builds = Retrieval.cacheChecks.builds
    Retrieval.expireCacheForChecks()
    _ = try search([wanted])
    precondition(Retrieval.cacheChecks.builds == builds + 1)
    Retrieval.invalidate()
    precondition(Retrieval.cacheChecks.entries == 0)
    var oversized = wanted
    oversized.text += String(repeating: "a", count: 2 * 1_024 * 1_024)
    // An oversized snapshot still works, but is never retained.
    try expect(try search([oversized]).first?.item == oversized)
    precondition(Retrieval.cacheChecks.entries == 0)
    DispatchQueue.concurrentPerform(iterations: 32) { iteration in
      do {
        let workspace: String? = iteration.isMultiple(of: 2) ? nil : "other"
        let hits = try Retrieval.retrieve("新規事業 提案書", candidates: [wanted, other, sameName], workspaceID: workspace, personID: nil)
        precondition(hits.allSatisfy { $0.item.workspaceID == workspace && $0.item.personID == nil })
        if workspace == nil { precondition(hits.first?.item == wanted) }
      } catch { fatalError("Concurrent retrieval failed: \(error)") }
    }
    Retrieval.invalidate()
  }
}
