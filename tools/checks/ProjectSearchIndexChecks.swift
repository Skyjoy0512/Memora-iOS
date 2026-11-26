import Foundation
import SQLite3

@main
struct ProjectSearchIndexChecks {
  static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("search.sqlite")
    let index = ProjectSearchIndex(fileURL: url)
    let project = UUID(), other = UUID()
    let source = ProjectCitation.Target.source(UUID())
    let otherSource = ProjectCitation.Target.source(UUID())
    let original = ProjectEvidenceInput(target: source, title: "箱根旅行", blocks: [ProjectSourceText(text: "箱根の移動時間を短くする", page: 2)])
    let unrelated = ProjectEvidenceInput(target: otherSource, title: "別件", blocks: [ProjectSourceText(text: "別プロジェクトの機密")])
    _ = try await index.retrieve(question: "機密", projectID: other, inputs: [unrelated])
    let first = try await index.retrieve(question: "移動時間", projectID: project, inputs: [original])
    precondition(!first.isEmpty && first.allSatisfy { $0.projectID == project && $0.target == source && $0.page == 2 })
    let repeatSearch = try await index.retrieve(question: "移動時間", projectID: project, inputs: [original])
    precondition(first == repeatSearch)
    let noMatch = try await index.retrieve(question: "量子計算チップ", projectID: project, inputs: [original])
    precondition(noMatch.isEmpty, "Unrelated sources used as unconditional index fallback")
    let followUp = try await index.retrieve(question: "もっと短く", projectID: project, inputs: [original])
    precondition(!followUp.isEmpty, "Explicit contextual follow-up lost its source candidates")
    try await index.remove(targets: [source])
    let rebuilt = try await index.retrieve(question: "移動時間", projectID: project, inputs: [original])
    precondition(rebuilt == first)
    await index.clearMemoryCache()
    let uncached = try await index.retrieve(question: "移動時間", projectID: project, inputs: [original])
    precondition(uncached == first)
    let reopened = ProjectSearchIndex(fileURL: url)
    let restored = try await reopened.retrieve(question: "箱根", projectID: project, inputs: [original])
    precondition(restored == first)
    var updated = original
    updated.blocks = [ProjectSourceText(text: "京都で宿泊", page: 3)]
    let changed = try await index.retrieve(question: "京都", projectID: project, inputs: [updated])
    precondition(changed.allSatisfy { $0.text == "京都で宿泊" && $0.page == 3 })
    let revoked = try await index.retrieve(question: "京都", projectID: project, inputs: [])
    precondition(revoked.isEmpty)
    let grantedAgain = try await index.retrieve(question: "京都", projectID: project, inputs: [updated])
    precondition(grantedAgain == changed)
    let removed = try await index.retrieve(question: "箱根", projectID: project, inputs: [])
    precondition(removed.isEmpty)
    let moved = try await index.retrieve(question: "京都", projectID: other, inputs: [updated])
    precondition(moved.allSatisfy { $0.projectID == other && $0.target == source })
    let strange = try await index.retrieve(question: "\" OR * ' ; DROP TABLE project_chunks; --", projectID: other, inputs: [updated])
    precondition(strange.allSatisfy { $0.projectID == other })
    let hundredProject = UUID()
    let hundred = (0..<100).map { i in
      ProjectEvidenceInput(target: .source(UUID()), title: String(repeating: "長い日本語プロジェクト名", count: 8) + "\(i)",
        blocks: [ProjectSourceText(text: i == 99 ? "特殊証拠を検索する" : "通常の資料\(i)")])
    }
    let many = try await index.retrieve(question: "特殊証拠", projectID: hundredProject, inputs: hundred)
    precondition(!many.isEmpty && many.contains { $0.target == hundred[99].target })
    try await index.remove(projectID: hundredProject)
    try await index.remove(targets: [source])
    var handle: OpaquePointer?
    precondition(sqlite3_open(url.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    precondition(sqlite3_prepare_v2(handle, "SELECT count(*) FROM project_chunks", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    precondition(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 0)
    _ = try await index.retrieve(question: "箱根", projectID: project, inputs: [original])
    try await index.remove(projectID: project)
    let empty = try await index.retrieve(question: "箱根", projectID: project, inputs: [])
    precondition(empty.isEmpty)
    let boundaryProject = UUID()
    let boundary = ProjectEvidenceInput(target: .source(UUID()), title: "上限", blocks: [
      ProjectSourceText(text: String(repeating: "🧑🏽‍💻箱根", count: 100_000), page: 9, time: 42)
    ])
    let large = try await index.retrieve(question: "箱根", projectID: boundaryProject, inputs: [boundary])
    let again = try await index.retrieve(question: "箱根", projectID: boundaryProject, inputs: [boundary])
    precondition(large == again && large.allSatisfy { $0.text.count <= 700 && $0.page == 9 && $0.time == 42 })
    try await index.remove(projectID: boundaryProject)
    let exactProject = UUID()
    var composed = ProjectEvidenceInput(target: .source(UUID()), title: "Café", blocks: [ProjectSourceText(text: "Café", time: 0)])
    _ = try await index.retrieve(question: "Café", projectID: exactProject, inputs: [composed])
    var decomposed = composed
    decomposed.title = "Cafe\u{301}"
    decomposed.blocks[0].text = "Cafe\u{301}"
    precondition(composed.title == decomposed.title && composed != decomposed)
    let exact = try await index.retrieve(question: "Café", projectID: exactProject, inputs: [decomposed])
    precondition(!exact.isEmpty && exact.allSatisfy { $0.text.utf8.elementsEqual(decomposed.blocks[0].text.utf8) && $0.title.utf8.elementsEqual(decomposed.title.utf8) })
    composed.blocks[0].time = -0.0
    precondition(composed.blocks[0].time == 0 && composed != ProjectEvidenceInput(target: composed.target, title: composed.title, blocks: [ProjectSourceText(text: "Café", time: 0)]))
    try await index.remove(projectID: exactProject)
    let kanaProject = UUID()
    let kana = ProjectEvidenceInput(target: .source(UUID()), title: "さくら", blocks: [ProjectSourceText(text: "さくらの資料")])
    let kanaNoise = ProjectEvidenceInput(target: .source(UUID()), title: "別件", blocks: [ProjectSourceText(text: "京都の費用")])
    let kanaMatches = try await index.retrieve(question: "さくら", projectID: kanaProject, inputs: [kana, kanaNoise])
    precondition(kanaMatches.count == 1 && kanaMatches.first?.target == kana.target)
    try await index.remove(projectID: kanaProject)
    let dateProject = UUID()
    var dated = ProjectEvidenceInput(target: .meeting(UUID()), title: "公開方針",
      blocks: [ProjectSourceText(text: "会議で公開方針を承認した。", time: 480)])
    let oldRows = try await index.retrieve(question: "公開方針", projectID: dateProject, inputs: [dated])
    precondition(oldRows.first?.recordedAt == nil && oldRows.first?.time == 480)
    let recordedAt = Date(timeIntervalSince1970: 1_789_560_000)
    dated.recordedAt = recordedAt
    let datedRows = try await index.retrieve(question: "公開方針", projectID: dateProject, inputs: [dated])
    precondition(datedRows.first?.recordedAt == recordedAt && datedRows.first?.time == 480)
    dated.recordedAt = recordedAt.addingTimeInterval(86_400)
    let updatedRows = try await index.retrieve(question: "公開方針", projectID: dateProject, inputs: [dated])
    precondition(updatedRows != datedRows && updatedRows.first?.recordedAt == dated.recordedAt)
    let reopenedRows = try await reopened.retrieve(question: "公開方針", projectID: dateProject, inputs: [dated])
    precondition(reopenedRows == updatedRows)
    print("ProjectSearchIndexChecks: passed (FTS5, persistence, date-only updates, removal, membership isolation, bound queries)")
  }
}
