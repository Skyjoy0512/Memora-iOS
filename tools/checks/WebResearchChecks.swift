import Foundation

@main
struct WebResearchChecks {
  static func main() throws {
    let request = try WebResearchClient.request(query: "箱根旅行", mode: .deepResearch, key: "fixture-key")
    precondition(request.url?.host == "api.search.brave.com" && request.url?.path == "/res/v1/llm/context")
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(items.first { $0.name == "maximum_number_of_urls" }?.value == "6")
    for query in ["", String(repeating: "a", count: 601), "bad\nquery"] {
      do { _ = try WebResearchClient.validate(query); preconditionFailure("invalid query accepted") } catch {}
    }
    let fixture = Data(#"{"grounding":{"generic":[{"title":"旅程","url":"https://example.com/plan?utm_source=test","snippets":["箱根で宿泊する。","移動は短くする。"]},{"title":"duplicate","url":"https://example.com/plan","snippets":["duplicate"]},{"title":"private","url":"https://127.0.0.1","snippets":["secret"]},{"title":"empty","url":"https://example.com/empty","snippets":[]}]}}"#.utf8)
    let sources = try WebResearchClient.decode(fixture, mode: .deepResearch)
    precondition(sources.count == 1 && sources[0].url.absoluteString == "https://example.com/plan")
    precondition(sources[0].kind == .extractedPassage && sources[0].text.contains("箱根"))
    let searchFixture = Data(#"{"web":{"results":[{"title":"記事","url":"https://example.com","description":"<strong>検索抜粋</strong>"}]}}"#.utf8)
    let snippets = try WebResearchClient.decode(searchFixture, mode: .search)
    precondition(snippets.count == 1 && snippets[0].kind == .searchExcerpt && snippets[0].text == "検索抜粋")
    for budget in [0, 20, 100, 2_000] {
      let context = WebResearchContext.build(sources, budget: budget)
      precondition(context.text.count <= budget)
    }
    let context = WebResearchContext.build(sources, budget: 2_000)
    precondition(WebResearchContext.cited("結果【Web1】【Web99】【Web1】", sent: context.sent) == [sources[0].id])
    let linked = WebResearchContext.linked("結果【Web1】【Web99】", sent: context.sent)
    precondition(String(linked.characters) == "結果【Web1】")
    precondition(linked.runs.compactMap(\.link) == [sources[0].url])
    let markdown = WebResearchContext.markdownLinked("結果【Web1】【Web99】【Web1】", sent: context.sent)
    precondition(!markdown.contains("99") && markdown.components(separatedBy: "memora-web-cite://1").count == 3)
    precondition(WebResearchContext.source(for: URL(string: "memora-web-cite://1")!, sent: context.sent)?.id == sources[0].id)
    precondition(WebResearchContext.source(for: URL(string: "memora-web-cite://99")!, sent: context.sent) == nil)
    let report = WebResearchReport(query: "旅行", mode: .deepResearch, queries: ["旅行"], sources: sources)
    let restored = try JSONDecoder().decode(WebResearchReport.self, from: JSONEncoder().encode(report))
    precondition(restored == report)
    print("WebResearchChecks: passed (bounded requests, source types, URL isolation, deduplication, budgets, citations, persistence)")
  }
}
