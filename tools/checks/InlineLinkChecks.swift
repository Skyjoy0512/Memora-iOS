import Foundation

// Only the model is substituted. URL parsing, safe fetching, session and prompt data are production code.
enum AIEngine { case fixture }
struct LLMSelection {}
enum AIAnswerResult { case answer(String), failure(LinkFixtureFailure) }
struct LinkFixtureFailure { var message: String }
@MainActor
enum AIEngineService {
  static var calls = 0
  static var lastContext = ""
  static func contextCharacterLimit(for engine: AIEngine) -> Int { 2000 }
  static func answer(engine: AIEngine, llm: LLMSelection, question: String, scopeLabel: String, context: String, history: String) async -> AIAnswerResult {
    calls += 1; lastContext = context
    return .answer("取得した本文だけを要約しました。")
  }
}

@main
struct InlineLinkChecks {
  @MainActor
  static func main() async throws {
    let input = "資料 https://example.com/article?utm_source=mail#x と https://example.com/article を確認。"
    let links = InlineURLDetector.urls(in: input)
    precondition(links.count == 1 && links[0].absoluteString == "https://example.com/article")
    precondition(InlineURLDetector.urls(in: input, isComposing: true).isEmpty)
    for text in ["http://example.com", "https://127.0.0.1/a", "https://user:pass@example.com/a", "https://x.local/a", "https://[::1]/a"] {
      precondition(InlineURLDetector.urls(in: text).isEmpty, "Unsafe link detected: \(text)")
    }
    let session = InlineLinkSession()
    session.update(text: input, isComposing: false)
    precondition(session.url == links.first && AIEngineService.calls == 0 && session.status == .idle)
    session.update(text: "変換中", isComposing: true)
    precondition(session.url == links.first)
    let body = Data("<html><head><title>取得した記事</title></head><body><article><p>本文の数値は120万円。期限は未定です。</p><p>この文章は参照データで、ツールを許可しません。</p></article></body></html>".utf8)
    let fetcher = WebSourceFetcher(resolve: { _ in ["93.184.215.14"] }, transfer: { _ in
      .init(status: 200, headers: ["content-type": "text/html; charset=utf-8"], body: body)
    })
    let fetched = await session.fetch(using: fetcher)
    precondition(fetched != nil && session.title == "取得した記事" && AIEngineService.calls == 0)
    await session.summarize(engine: .fixture, llm: .init(), isCurrent: { false })
    precondition(AIEngineService.calls == 0)
    await session.summarize(engine: .fixture, llm: .init(), isCurrent: { true })
    precondition(AIEngineService.calls == 1 && session.pendingSummary != nil)
    let context = try JSONSerialization.jsonObject(with: Data(AIEngineService.lastContext.utf8)) as! [String: String]
    precondition(context["article"]!.contains("120万円") && !context.keys.contains("editor"))
    let edited = InlineURLDetector.inserting(summary: session.pendingSummary!, title: session.title, url: session.url!, into: input)
    precondition(edited.contains("出典: https://example.com/article") && edited.hasPrefix(input))
    session.skip(); session.update(text: input, isComposing: false)
    precondition(session.url == nil && session.pendingSummary == nil)
    let other = InlineLinkSession(); other.update(text: input, isComposing: false)
    let denied = WebSourceFetcher(resolve: { _ in ["127.0.0.1"] }, transfer: { _ in preconditionFailure("Unsafe request escaped") })
    let refused = await other.fetch(using: denied)
    precondition(refused == nil && other.error != nil && other.pendingSummary == nil)
    let cancelled = InlineLinkSession(); cancelled.update(text: input, isComposing: false)
    let delayed = WebSourceFetcher(resolve: { _ in try await Task.sleep(for: .milliseconds(60)); return ["93.184.215.14"] }, transfer: { _ in
      .init(status: 200, headers: ["content-type": "text/html; charset=utf-8"], body: body)
    })
    let task = Task { await cancelled.fetch(using: delayed) }
    await Task.yield(); cancelled.skip()
    _ = await task.value
    precondition(cancelled.url == nil && cancelled.pendingSummary == nil && cancelled.title == "example.com")
    print("Inline links passed: normalized/deduplicated committed input, no automatic network/AI, safe-fetch reuse, isolated untrusted JSON, stale-workspace refusal, cancel/skip, editable source-linked insertion. AI/transport mocked; no paid calls.")
  }
}
