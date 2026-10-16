import Foundation

@main struct ResearchLoopChecks {
  @MainActor static func main() async throws {
    let sample = WebResearchSource(title: "架空統計", url: URL(string: "https://example.invalid/a")!, text: "架空の取得根拠", kind: .searchExcerpt)
    var calls: [String] = []
    let original = WebResearchReport(query: "国内市場", mode: .deepResearch, queries: ["国内市場", "市場の統計", "市場の比較"])
    let complete = await ResearchLoop.run(original, isAuthorized: { true }, search: { query in calls.append(query); return [sample, sample] }, publish: { _ in true })
    precondition(calls.count <= 6 && calls.count > 3 && Set(calls).count == calls.count)
    precondition(complete.sources.count == 1 && complete.coverageGaps?.isEmpty == false)
    precondition(complete.completedQueries?.count == calls.count)
    enum MockError: Error { case failure }
    calls = []
    let failed = await ResearchLoop.run(original, isAuthorized: { true }, search: { query in
      calls.append(query); if calls.count == 2 { throw MockError.failure }; return [sample]
    }, publish: { _ in true })
    precondition(failed.status == .failed && failed.sources.count == 1 && calls.count == 2)
    var allowed = true
    let stopped = await ResearchLoop.run(original, isAuthorized: { allowed }, search: { _ in [sample] }, publish: { report in
      if !(report.completedQueries ?? []).isEmpty { allowed = false }; return true
    })
    precondition(stopped.status == .interrupted && stopped.sources.count == 1)
    let empty = await ResearchLoop.run(WebResearchReport(query: "空", mode: .search, queries: ["空"]), isAuthorized: { true }, search: { _ in [] }, publish: { _ in true })
    precondition(empty.status == .failed && empty.sources.isEmpty)
    let saveFailure = await ResearchLoop.run(original, isAuthorized: { true }, search: { _ in preconditionFailure() }, publish: { _ in false })
    precondition(saveFailure.status == .interrupted)
    let replay = await ResearchLoop.run(complete, isAuthorized: { true }, search: { _ in preconditionFailure() }, publish: { _ in true })
    precondition(replay.status == .failed)
    var clockCalls = 0
    let timeout = await ResearchLoop.run(original, now: { clockCalls += 1; return Date(timeIntervalSince1970: clockCalls == 1 ? 0 : 121) }, isAuthorized: { true }, search: { _ in preconditionFailure() }, publish: { _ in true })
    precondition(timeout.status == .interrupted)
    precondition(ResearchPlan.hasInvalidCitations("根拠【Web2】", sourceCount: 1))
    precondition(!ResearchPlan.hasInvalidCitations("根拠【Web1】", sourceCount: 1))
    let draft = MailDraft(recipients: [], subject: "議事録", body: "確認をお願いします", cc: ["test@example.invalid"])
    let reloaded = try JSONDecoder().decode(MailDraft.self, from: JSONEncoder().encode(draft))
    precondition(reloaded == draft && reloaded.status == .draft && reloaded.recipients.isEmpty)
    precondition(!MailDraft.validAddress("田中さん") && !MailDraft.validAddress("a@example.invalid\r\nBCC: injected"))
    precondition(MailDraft.validAddress("person@example.invalid"))
    print("ResearchLoopChecks: passed (production iterative loop, bound/dedupe/error/partial/revoke/timeout/save failure/replay/empty/citations; draft persistence, unknown recipient, header injection; mocks only)")
  }
}
