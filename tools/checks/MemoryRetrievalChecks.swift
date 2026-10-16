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
    let bulk = (0..<2_000).map { index in MemoryRetrievalItem(id: UUID(), kind: .episode, text: "会議番号\(index) 開発計画の進捗確認", updatedAt: date, sourceID: UUID()) }
    let start = Date()
    let large = try MemoryRetrievalOrchestrator.retrieve("開発計画の進捗", candidates: bulk, workspaceID: nil, personID: nil)
    precondition(large.count <= 5)
    print("MemoryRetrievalChecks: passed (legacy, validity, conflict states, sensitivity, Japanese FTS5, scope, delete, 2000 items \(Date().timeIntervalSince(start))s; no LLM quality claim)")
  }
}
