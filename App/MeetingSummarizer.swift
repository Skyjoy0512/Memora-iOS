import Foundation

/// Writes a summary with whichever engine was chosen. The cloud reads the whole
/// transcript and writes the document itself; the on-device model works
/// section by section and the app lays the document out. Both return the same
/// shape, so the record is filed the same way either way.
enum MeetingSummarizer {
  static func summarize(
    _ input: MeetingSummaryInput,
    engine: AIEngine,
    llm: LLMSelection,
    authorize: (@MainActor () -> Bool)? = nil,
    progress: @escaping @MainActor (String) -> Void
  ) async -> Result<MeetingSummary, AIAnswerFailure> {
    await AudioProcessingDiagnostics.trace(.summary, audioSeconds: input.duration) {
      let diagnostic = AudioProcessingDiagnostics.current
      let effective = AIEngineService.effectiveEngine(engine)
      diagnostic?.setEngine(effective == .cloud || effective == .memora ? .cloudSummary : .onDeviceSummary)
      let span = diagnostic?.begin(.summary, audioSeconds: input.duration)
      let result = await performSummary(input, engine: engine, llm: llm, authorize: authorize, progress: progress)
      let outcome: AudioDiagnosticReport.Outcome
      switch result {
      case .success: outcome = .success
      case .failure(.cancelled): outcome = .cancelled
      case .failure: outcome = .failed
      }
      diagnostic?.end(span, outcome: outcome)
      return result
    } outcome: { result in
      switch result {
      case .success: .success
      case .failure(.cancelled): .cancelled
      case .failure: .failed
      }
    }
  }

  private static func performSummary(_ input: MeetingSummaryInput, engine: AIEngine, llm: LLMSelection,
                                     authorize: (@MainActor () -> Bool)?,
                                     progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> {
    guard input.transcript.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      return .failure(.empty)
    }
    SummaryDiagnostics.current?.record(.analysis)

    switch AIEngineService.effectiveEngine(engine) {
    case .foundation, .automatic:
      guard #available(iOS 26.0, *) else { return .failure(.noEngine) }
      return await OnDeviceSummarizer.summarize(input, progress: progress)
    case .local:
      // A local LLM still needs a bundled model; this build has none.
      return .failure(.notBundled)
    case .cloud, .memora:
      return await cloud(input, llm: llm, authorize: authorize, progress: progress)
    }
  }

  /// What the chosen engine will do, for the sheet to say before generating.
  static func approach(for engine: AIEngine, llm: LLMSelection) -> String {
    switch AIEngineService.effectiveEngine(engine) {
    case .cloud, .memora:
      "\(llm.modelLabel)が文字起こし全体を読んで詳しく作成します。"
    case .foundation:
      "端末内AIが区間ごとに整理して組み立てます。クラウドより簡潔になり、長い会議は数分かかります。"
    case .automatic:
      "この端末では端末内AIを使えません。設定の「AI整理」でクラウドを選んでください。"
    case .local:
      "ローカルLLMはまだ利用できません。別のエンジンを選んでください。"
    }
  }

  private static func cloud(
    _ input: MeetingSummaryInput,
    llm: LLMSelection,
    authorize: (@MainActor () -> Bool)?,
    progress: @escaping @MainActor (String) -> Void
  ) async -> Result<MeetingSummary, AIAnswerFailure> {
    let endpoint = llm.baseURL.appendingPathComponent(llm.provider.usesAnthropicAPI ? "messages" : "chat/completions")
    let transport = CloudHTTPTransport(endpoint: endpoint)
    defer { transport.invalidate() }
    let sourceIndex = SummarySourceIndex(input.transcript)
    let originalUnits = sourceIndex.units(hasTimestamps: input.duration > 0, compact: false)
    let compactUnits = sourceIndex.units(hasTimestamps: input.duration > 0, compact: true)
    let sourceLegend = sourceIndex.legend
    let compactBytes = sourceLegend.utf8.count + 1 + compactUnits.reduce(0) { $0 + $1.prefix.utf8.count + $1.text.utf8.count + 1 }
    let originalBytes = originalUnits.reduce(0) { $0 + $1.prefix.utf8.count + $1.text.utf8.count + 1 }
    let compact = compactBytes < originalBytes
    let units = compact ? compactUnits : originalUnits
    let legend = compact ? sourceLegend + "\n" : ""
    let instructions = [SummaryPrompt.document(for: input, transcript: ""),
      SummaryPrompt.partNotes(for: input, part: 512, of: 512, range: "999:59〜999:59", transcript: ""),
      SummaryPrompt.intermediateMerge(for: input, notes: ""), SummaryPrompt.merge(for: input, notes: "")]
      .max { $0.utf8.count < $1.utf8.count } ?? ""
    guard let budget = SummaryTokenBudget(capabilities: ModelCapabilityRegistry.capabilities(for: llm),
      outputReservation: ModelCapabilityRegistry.outputReservation(for: llm),
      instructionText: SummaryPrompt.system + instructions + legend) else { return .failure(.contextTooLarge) }
    let parts: [[String]]
    switch SummaryInputPartition.make(units, capacity: budget.sourceCapacity) {
    case .failure(let failure): return .failure(failure)
    case .success(let value): parts = value
    }
    SummaryDiagnostics.current?.record(.sourceWireBytes, code: compact ? compactBytes : originalBytes)
    SummaryDiagnostics.current?.record(.sourceOriginalBytes, code: originalBytes)
    SummaryDiagnostics.current?.record(.plannedParts, code: parts.count)
    SummaryDiagnostics.current?.record(.planningCapacity, code: budget.sourceCapacity)

    let request: String
    if parts.count == 1 {
      await progress("文字起こし全体を読んでいます")
      request = SummaryPrompt.document(for: input, transcript: legend + parts[0].joined(separator: "\n"))
    } else {
      guard parts.count <= 512 else { return .failure(.executionLimit) }
      let collected = await SummaryPartScheduler.collect(count: parts.count,
        maximumConcurrent: SummaryGenerationPolicy.parallelParts(input.preferences.processingMode, llm: llm)) { index in
        let part = parts[index]
        progress("長い会議を分けて整理中（\(index + 1)/\(parts.count)）")
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let range = timeRange(of: part)
        let result = await CloudAIService.completeStreaming(
          system: SummaryPrompt.system,
          user: SummaryPrompt.partNotes(
            for: input,
            part: index + 1,
            of: parts.count,
            range: range,
            transcript: legend + part.joined(separator: "\n")
          ),
          llm: llm,
          transport: transport,
          processingMode: input.preferences.processingMode,
          authorize: authorize,
          onActivity: { progress("長い会議を分けて整理中（\(index + 1)/\(parts.count)）") }
        ) { count in
          progress("長い会議を分けて整理中（\(index + 1)/\(parts.count)・\(count)文字）")
        }
        switch result {
        case .answer(let text): return .success("# 部分\(index + 1)（\(range)）\n\(text)")
        case .failure(let failure): return .failure(failure)
        }
      }
      let notes: [String]
      switch collected {
      case .success(let collected): notes = collected
      case .failure(let failure): return .failure(failure)
      }
      let reduced = await SummaryNoteHierarchy.reduce(notes, limit: budget.sourceCapacity, measure: SummaryTokenBudget.upperBound) { group in
        progress("全体をまとめています")
        let result = await CloudAIService.completeStreaming(
          system: SummaryPrompt.system,
          user: SummaryPrompt.intermediateMerge(for: input, notes: legend + group.joined(separator: "\n\n")),
          llm: llm, transport: transport, processingMode: input.preferences.processingMode, authorize: authorize,
          onActivity: { progress("全体をまとめています") }
        ) { _ in progress("全体をまとめています") }
        switch result {
        case .answer(let text): return .success(text)
        case .failure(let failure): return .failure(failure)
        }
      }
      switch reduced {
      case .failure(let failure): return .failure(failure)
      case .success(let notes):
        await progress("全体をまとめています")
        request = SummaryPrompt.merge(for: input, notes: legend + notes.joined(separator: "\n\n"))
      }
    }

    guard !Task.isCancelled else { return .failure(.cancelled) }
    SummaryDiagnostics.current?.record(.generation)
    let reply = await CloudAIService.completeStreaming(
      system: SummaryPrompt.system,
      user: request,
      llm: llm,
      transport: transport,
      processingMode: input.preferences.processingMode,
      authorize: authorize,
      onActivity: { progress("要約を作成しています") }
    ) { count in
      progress("AIが書いています（\(count)文字）")
    }
    switch reply {
    case .answer(let reply):
      SummaryDiagnostics.current?.record(.parseStarted)
      let choices = input.automaticCandidates.isEmpty ? [input.template] : input.automaticCandidates
      let actionFree = choices.compactMap { choice -> String? in
        if case .market(let template) = choice, !template.includesActions { return choice.id }
        return nil
      }
      var summary = SummaryResponseParser.validateTemplate(SummaryResponseParser.parse(reply),
        allowedIDs: Set(choices.map(\.id)), actionFreeIDs: Set(actionFree))
      guard summary.hasCompleteExtraction else { return .failure(.generationFailed) }
      summary.evidence = summary.evidence.compactMap { reference in
        guard let id = sourceIndex.originalID(for: reference.sourceSegmentID, allowShortIDs: compact),
              sourceIndex.validates(id: reference.sourceSegmentID, quote: reference.quote) else { return nil }
        var reference = reference
        reference.sourceSegmentID = id.uuidString
        return reference
      }
      if var knowledge = summary.knowledge {
        for index in knowledge.facts.indices {
          guard var references = knowledge.facts[index].sourceReferences else { continue }
          for reference in references.indices {
            if let id = sourceIndex.originalID(for: references[reference].sourceSegmentID, allowShortIDs: compact) {
              references[reference].sourceSegmentID = id.uuidString
            }
          }
          knowledge.facts[index].sourceReferences = references
        }
        summary.knowledge = knowledge
      }
      summary.knowledge = summary.knowledge?.validated(allowedProfiles: Set(choices.map(\.id))) { reference in
        sourceIndex.validates(id: reference.sourceSegmentID, quote: reference.quote, allowShortIDs: false)
      }
      if var knowledge = summary.knowledge {
        if knowledge.selectedProfileIDs.isEmpty, let id = summary.templateID { knowledge.selectedProfileIDs = [id] }
        let speakerIDs = Set(input.transcript.compactMap(\.speakerID))
        for index in knowledge.facts.indices {
          knowledge.facts[index].origin = .generated
          knowledge.facts[index].speakerIDs = knowledge.facts[index].speakerIDs?.filter { speakerIDs.contains($0) }
        }
        summary.knowledge = knowledge
      }
      if !input.template.preservesFormat { summary.markdown = SummaryResponseParser.generatedMarkdown(summary.markdown) }
      if summary.templateID == VideoSummaryTemplate.template.id { summary.decisions = [] }
      SummaryDiagnostics.current?.record(.parseCompleted)
      return summary.markdown.isEmpty ? .failure(.empty) : .success(summary)
    case .failure(let failure):
      return .failure(failure)
    }
  }

  /// "mm:ss〜mm:ss" read off the first and last line of a part.
  private static func timeRange(of part: [String]) -> String {
    func stamp(_ line: String?) -> String {
      guard let line, line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return "" }
      return String(line[line.index(after: line.startIndex)..<end])
    }
    return "\(stamp(part.first))〜\(stamp(part.last))"
  }
}
