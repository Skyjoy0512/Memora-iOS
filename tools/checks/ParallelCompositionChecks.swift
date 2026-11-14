import Foundation

@MainActor enum ParallelCompositionChecks {
  static func run() async throws {
    let input = MeetingSummaryInput(title: "公開条件の見直し", date: .distantPast, duration: 3600,
      participantNames: [], transcript: [
        .init(id: UUID(), speaker: "A", speakerIsCertain: false, timestamp: 0, text: "当初の公開日は11月20日でした。予算は150万円です。"),
        .init(id: UUID(), speaker: "B", speakerIsCertain: false, timestamp: 3500, text: "当初の公開決定を撤回します。性能試験と監査承認が終わるまで公開しません。")
      ], template: .standard, preferences: .init(length: .detailed, processingMode: .accurate))
    let llm = LLMSelection(provider: .openAI, modelID: "gpt-6-sol")
    precondition(!SummaryOptimizationGate.permitsParallelComposition(input: input, llm: llm, sourceBytes: 100_000),
      "Unreviewed multi-request route became a production default")
    let source = SummarySourceIndex(input.transcript)
    let transport = CloudHTTPTransport(endpoint: llm.baseURL.appendingPathComponent("chat/completions"))
    defer { transport.invalidate() }
    for compact in [false, true] {
      let ids = input.transcript.enumerated().map { compact ? "S\($0.offset + 1)" : $0.element.id.uuidString }
      let decision = "性能試験と監査承認が終わるまで公開しません。"
      let knowledge = SummaryKnowledge(selectedProfileIDs: [input.template.id], contentType: .meeting,
        topics: [.init(id: "release", title: "公開条件"), .init(id: "budget", title: "予算")], facts: [
          .init(id: "current", category: .decision, content: decision, status: .confirmed, relatedTopicID: "release",
            sourceReferences: [.init(sourceSegmentID: ids[1], quote: decision)]),
          .init(id: "withdrawal", category: .rejectedOption, content: "当初の公開決定を撤回", status: .confirmed,
            relatedTopicID: "release", relatedFactIDs: ["current"],
            sourceReferences: [.init(sourceSegmentID: ids[1], quote: "当初の公開決定を撤回します。")]),
          .init(id: "cost", category: .number, content: "予算150万円", status: .confirmed, relatedTopicID: "budget",
            sourceReferences: [.init(sourceSegmentID: ids[0], quote: "予算は150万円です。")])
        ])
      let plan = SummaryCompositionPlan(schemaVersion: 1, overview: "公開は試験と承認後に判断する。", sections: [
        .init(id: "release", title: "公開決定の撤回と条件", sourceSegmentIDs: [ids[1]]),
        .init(id: "budget", title: "予算150万円", sourceSegmentIDs: [ids[0]])
      ], extraction: .init(templateID: input.template.id, knowledge: knowledge, decisions: [decision], actions: []))
      precondition(plan.isValid(input: input, source: source, compact: compact))
      var invalid = plan
      invalid.extraction.decisions = ["11月20日に公開する"]
      precondition(!invalid.isValid(input: input, source: source, compact: compact))
      invalid = plan
      invalid.extraction.knowledge.facts[0].sourceReferences?[0].sourceSegmentID = "S9999"
      precondition(!invalid.isValid(input: input, source: source, compact: compact))
      invalid = plan
      invalid.extraction.knowledge.facts.append(.init(id: "task", category: .action, content: "公開の準備", status: .confirmed,
        sourceReferences: [.init(sourceSegmentID: ids[1], quote: decision)]))
      invalid.extraction.actions = [.init(title: "公開の準備", owner: "架空の社長", due: nil)]
      precondition(!invalid.isValid(input: input, source: source, compact: compact))
      let encoded = try JSONEncoder().encode(plan)
      var broken = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
      var extraction = broken["extraction"] as! [String: Any]
      var facts = extraction["knowledge"] as! [String: Any]
      facts["facts"] = (facts["facts"] as! [[String: Any]]) + [["id": "broken"]]
      extraction["knowledge"] = facts; broken["extraction"] = extraction
      let brokenData = try JSONSerialization.data(withJSONObject: broken)
      precondition(SummaryCompositionPlan.decode(String(decoding: brokenData, as: UTF8.self)) == nil,
        "Recoverable legacy enrichment hid a damaged new global plan")
      var prose = plan
      prose.sections = []
      prose.extraction.knowledge.topics = []
      prose.extraction.knowledge.facts = []
      prose.extraction.decisions = []
      precondition(prose.isValid(input: input, source: source, compact: compact), "Minimum headings were forced")
      let proseGate = SummaryFixtureGate()
      CloudAIService.gate = proseGate
      let proseTask = Task { await MeetingSummarizer.composeInParallel(input, llm: llm,
        transcript: source.units(hasTimestamps: true, compact: compact).map(\.line).joined(separator: "\n"),
        source: source, compact: compact, transport: transport, authorize: { true }, progress: { _ in }) }
      await SummaryPipelineChecks.wait { proseGate.pending.count == 1 }
      proseGate.finish(0, .answer(String(decoding: try JSONEncoder().encode(prose), as: UTF8.self)))
      guard case .success(let proseSummary) = await proseTask.value else { preconditionFailure() }
      precondition(proseGate.calls.count == 1 && !proseSummary.markdown.contains("## "))
      for failure in [false, true] {
        let gate = SummaryFixtureGate()
        CloudAIService.gate = gate
        let task = Task { await MeetingSummarizer.composeInParallel(input, llm: llm,
          transcript: source.units(hasTimestamps: true, compact: compact).map(\.line).joined(separator: "\n"),
          source: source, compact: compact, transport: transport, authorize: { true }, progress: { _ in }) }
        await SummaryPipelineChecks.wait { gate.pending.count == 1 }
        gate.finish(0, .answer(String(decoding: encoded, as: UTF8.self)))
        let width = SummaryGenerationPolicy.parallelParts(.accurate, llm: llm)
        await SummaryPipelineChecks.wait { gate.pending.count == width }
        precondition(gate.calls[1].user.contains(input.transcript[0].text) && gate.calls[1].user.contains(input.transcript[1].text))
        precondition(gate.calls[1].user.contains("withdrawal") && gate.calls[1].user.contains(decision))
        if failure {
          gate.finish(1, .failure(.rateLimited))
          guard case .failure(.rateLimited) = await task.value else { preconditionFailure() }
          precondition(gate.calls.count == 1 + width && gate.pending.isEmpty)
        } else {
          var finished = 0
          while finished < 2 {
            await SummaryPipelineChecks.wait { !gate.pending.isEmpty }
            for call in gate.pending.keys.sorted().reversed() {
              let isRelease = gate.calls[call].user.contains("セクションID: release")
              gate.finish(call, .answer(isRelease ? "当初決定を撤回。" + decision : "予算は150万円です。"))
              finished += 1
            }
          }
          guard case .success(let summary) = await task.value else { preconditionFailure("Parallel composition failed") }
          precondition(summary.decisions == [decision] && summary.actions.isEmpty && summary.knowledge?.facts.count == 3)
          precondition(summary.evidence.allSatisfy { source.originalID(for: $0.sourceSegmentID, allowShortIDs: false) != nil })
          precondition(summary.markdown.range(of: "公開決定の撤回と条件")!.lowerBound < summary.markdown.range(of: "## 予算150万円")!.lowerBound)
          precondition(gate.calls.count == 3 && Set(gate.calls.compactMap(\.transportID)).count == 1)
        }
      }
    }
    print("ParallelCompositionChecks: PASS; production candidate with mocked inference, whole-source/shared reversal context, reverse arrival, common parser and UUID evidence, 429 fail-stop and malformed-plan refusal. Release gate remains closed; no model quality/cost/speed claim.")
  }
}
