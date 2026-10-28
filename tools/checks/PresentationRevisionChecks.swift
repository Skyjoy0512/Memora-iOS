import Foundation

enum PresentationRevisionChecks {
  @MainActor static func run() async throws {
    for layout in SlideArchetype.allCases {
      let slide = PresentationExample.slide(layout)
      let other = DocumentSlide(title: "送信しない別ページ", bullets: ["送信しない秘密"])
      let document = MemoraDocument(title: "架空の検査", kind: .slides, slides: [slide, other])
      let request = try PresentationRevision.request(document: document, selectedIDs: [slide.id], instruction: "短い見出しにする", contextLimit: 24_000)
      precondition(!request.context.contains("送信しない"))
      let responseText = try response(for: request)
      let revision = try PresentationRevision.decode(responseText, for: request)
      let result = try revision.applying(to: document)
      precondition(result.slides[0].id == slide.id && result.slides[0].title == "判断に必要な事実を共有")
      precondition(result.slides[1] == other && result.slides[0].composition == slide.composition)
      precondition(document.slides[0] == slide && result.contentRevision == nil)
      var stale = document; stale.slides[0].notes += "別の編集"
      do { _ = try revision.applying(to: stale); preconditionFailure("Stale slide overwritten") } catch {}
      let bad = try response(for: request) { rows in rows[0]["title"] = "新しい99999という数字" }
      do { _ = try PresentationRevision.decode(bad, for: request); preconditionFailure("Invented number accepted") } catch {}
    }
    let slide = PresentationExample.slide(.b24)
    let document = MemoraDocument(title: "検査", kind: .slides, slides: [slide])
    let request = try PresentationRevision.request(document: document, selectedIDs: [slide.id], instruction: "主張を短く", contextLimit: 24_000)
    for selected: Set<UUID> in [[], [UUID()], Set((0..<4).map { _ in UUID() })] {
      do { _ = try PresentationRevision.request(document: document, selectedIDs: selected, instruction: "修正", contextLimit: 24_000); preconditionFailure("Invalid selection") } catch {}
    }
    do { _ = try PresentationRevision.request(document: document, selectedIDs: [slide.id], instruction: "修正", contextLimit: 10); preconditionFailure("Truncated input") } catch {}
    for mutate: (inout [[String: Any]]) throws -> Void in [
      { $0[0]["slide_id"] = UUID().uuidString },
      { $0[0]["unexpected"] = "tool" },
      { $0.removeAll() },
      { $0.append($0[0]) },
      { rows in
        var content = slide.composition!; content.sources?[0].locator = "偽の出典"
        rows[0]["content_json"] = String(data: try JSONEncoder().encode(content), encoding: .utf8)!
      },
      { rows in
        var content = slide.composition!; content.chart?.series[0].values.swapAt(0, 1)
        rows[0]["content_json"] = String(data: try JSONEncoder().encode(content), encoding: .utf8)!
      }
    ] {
      do { _ = try PresentationRevision.decode(try response(for: request, mutate: mutate), for: request); preconditionFailure("Bad revision accepted") } catch {}
    }
    let session = PresentationRevisionSession()
    let numbered = DocumentSlide(title: "一つの施策で１５万円を確認", bullets: [])
    let numberedRequest = try PresentationRevision.request(document: .init(title: "検査", kind: .slides, slides: [numbered]),
      selectedIDs: [numbered.id], instruction: "表記を整える", contextLimit: 24_000)
    _ = try PresentationRevision.decode(try response(for: numberedRequest) { $0[0]["title"] = "一つの施策で15万円を確認" }, for: numberedRequest)
    do {
      _ = try PresentationRevision.decode(try response(for: numberedRequest) { $0[0]["title"] = "二つの施策で15万円を確認" }, for: numberedRequest)
      preconditionFailure("Changed Japanese number accepted")
    } catch {}
    var metric = PresentationExample.slide(.m03)
    metric.composition?.metrics = [.init(label: "指標|15.0", value: 30, unit: "%")]
    let metricRequest = try PresentationRevision.request(document: .init(title: "検査", kind: .slides, slides: [metric]),
      selectedIDs: [metric.id], instruction: "見出しを短く", contextLimit: 24_000)
    do {
      _ = try PresentationRevision.decode(try response(for: metricRequest) { rows in
        var changed = metric.composition!
        changed.metrics = [.init(label: "指標", value: 15, unit: "30.0|%")]
        rows[0]["content_json"] = String(data: try JSONEncoder().encode(changed), encoding: .utf8)!
      }, for: metricRequest)
      preconditionFailure("Delimiter collision altered a protected metric")
    } catch {}
    var calls = 0
    let answer = try response(for: request)
    await session.generate(request, isCurrent: { false }) { calls += 1; return .answer(answer) }
    precondition(calls == 0 && session.proposal == nil)
    var checks = 0
    await session.generate(request, isCurrent: { checks += 1; return checks == 1 }) { calls += 1; return .answer(answer) }
    precondition(calls == 0, "Scheduled request skipped final authorization")
    var authorized = true
    await session.generate(request, isCurrent: { authorized }) { calls += 1; return .answer(answer) }
    precondition(calls == 1 && session.proposal != nil && !session.isBusy)
    authorized = false
    do { _ = try session.accept(in: document); preconditionFailure("Stale permission applied") } catch {}
    authorized = true
    var delayedReply: CheckedContinuation<AIAnswerResult, Never>?
    let delayed = Task { await session.generate(request, isCurrent: { authorized }) {
      calls += 1
      return await withCheckedContinuation { delayedReply = $0 }
    } }
    await waitUntil { session.isBusy && calls == 2 && delayedReply != nil }
    await session.generate(request, isCurrent: { true }) { calls += 1; return .answer(answer) }
    precondition(calls == 2, "Concurrent duplicate request")
    authorized = false
    await waitUntil { !session.isBusy && session.failure != nil }
    precondition(!session.isBusy && session.proposal == nil && session.failure != nil)
    authorized = true
    delayedReply?.resume(returning: .answer(answer)); delayedReply = nil
    await delayed.value
    precondition(session.proposal == nil, "Revocation revived after OFF/ON")
    var lateReply: CheckedContinuation<AIAnswerResult, Never>?
    let late = Task { await session.generate(request, isCurrent: { true }) {
      await withCheckedContinuation { lateReply = $0 }
    } }
    await waitUntil { session.isBusy && lateReply != nil }; session.cancel()
    await session.generate(request, isCurrent: { true }) { .failure(.network) }
    lateReply?.resume(returning: .answer(answer)); lateReply = nil
    await late.value
    precondition(session.proposal == nil && session.failure == AIAnswerFailure.network.message)
    await session.generate(request, isCurrent: { true }) { .answer(answer) }
    let applied = try session.accept(in: document)
    precondition(applied.slides[0].title == "判断に必要な事実を共有" && session.proposal == nil)
    print("Presentation revisions passed: all 65 layouts, selected-only payload, preserved IDs/numbers/sources/chart data, malformed/stale rejection, single request, cancel/replacement, live revocation and explicit draft apply; AI mocked, no API calls")
  }

  @MainActor static func waitUntil(_ ready: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
      if ready() { return }
      try? await Task.sleep(for: .milliseconds(2))
    }
    precondition(ready(), "Fixture operation did not start")
  }

  static func response(for request: PresentationRevision.Request,
                       mutate: (inout [[String: Any]]) throws -> Void = { _ in }) throws -> String {
    var rows: [[String: Any]] = try request.originals.map { slide in
      var row: [String: Any] = ["slide_id": slide.id.uuidString, "title": "判断に必要な事実を共有", "bullets": slide.bullets, "notes": slide.notes]
      if let content = slide.composition {
        row["layout"] = content.layout.rawValue
        row["content_json"] = String(data: try JSONEncoder().encode(content), encoding: .utf8)!
      }
      return row
    }
    try mutate(&rows)
    return String(data: try JSONSerialization.data(withJSONObject: ["slides": rows]), encoding: .utf8)!
  }
}
