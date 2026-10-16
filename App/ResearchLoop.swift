import Foundation

/// The same bounded loop runs with the real transport or isolated mock sources.
enum ResearchLoop {
  @MainActor
  static func run(_ original: WebResearchReport, now: () -> Date = { .now },
                  isAuthorized: () -> Bool,
                  search: (String) async throws -> [WebResearchSource],
                  publish: (WebResearchReport) -> Bool) async -> WebResearchReport {
    var report = original
    guard (report.attemptedQueries ?? []).isEmpty, (1...3).contains(report.queries.count) else {
      report.status = .failed; report.error = "実行済みの検索は再送しません。新しい調査を開始してください。"
      return report
    }
    let started = now()
    var pending = report.queries, position = 0
    var seen = Set(report.sources.map(\.url))
    do {
      while position < pending.count {
        try Task.checkCancellation()
        guard isAuthorized(), now().timeIntervalSince(started) < ResearchPlan.maximumSeconds,
              (report.attemptedQueries?.count ?? 0) < (report.mode == .search ? 1 : ResearchPlan.maximumSearches) else { throw CancellationError() }
        let query = pending[position]; position += 1
        report.attemptedQueries = (report.attemptedQueries ?? []) + [query]
        report.progressEvents = (report.progressEvents ?? []) + ["検索を開始: " + query]
        guard publish(report) else { throw CancellationError() }
        let sources = try await search(query)
        try Task.checkCancellation()
        guard isAuthorized() else { throw CancellationError() }
        for source in sources.prefix(20) {
          if let index = report.sources.firstIndex(where: { $0.url == source.url }) {
            if !report.sources[index].text.contains(source.text) { report.sources[index].text = String((report.sources[index].text + "\n\n" + source.text).prefix(8_000)) }
          } else if seen.insert(source.url).inserted && report.sources.count < ResearchPlan.maximumSources { report.sources.append(source) }
        }
        report.completedQueries = (report.completedQueries ?? []) + [query]
        report.coverageGaps = ResearchPlan.gaps(in: report.sources)
        report.progressEvents = (report.progressEvents ?? []) + ["取得元と不足情報を確認: \(report.sources.count)件"]
        if report.mode == .deepResearch, position == pending.count,
           let next = ResearchPlan.nextQuery(topic: report.query, attempted: pending, sources: report.sources) {
          pending.append(next); report.queries.append(next)
          report.progressEvents = (report.progressEvents ?? []) + ["不足情報の追加検索を計画: " + next]
        }
        guard publish(report) else { throw CancellationError() }
      }
      if report.sources.isEmpty { report.status = .failed; report.error = "取得できる根拠がありません。" }
    } catch {
      report.status = Task.isCancelled || error is CancellationError ? .interrupted : .failed
      report.error = report.status == .interrupted ? "時間・権限・保存・停止条件により調査を中断しました。取得済み根拠は保持しています。" : "検索に失敗しました。取得済み根拠は保持し、自動再送はしません。"
    }
    return report
  }
}
