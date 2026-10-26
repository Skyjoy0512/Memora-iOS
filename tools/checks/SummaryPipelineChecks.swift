import Foundation

/// Production orchestration and parser; only provider/OS inference is replaced.
@main @MainActor
enum SummaryPipelineChecks {
  static func main() async throws {
    for empty in ["", " \n\t　"] {
      CloudAIService.gate = SummaryFixtureGate()
      var input = makeInput(mode: .fast)
      input.transcript = [input.transcript[0]]
      input.transcript[0].text = empty
      let result = await MeetingSummarizer.summarize(input, engine: .cloud,
        llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in })
      guard case .failure(.empty) = result else { throw NSError(domain: "SummaryPipelineChecks.empty", code: 1) }
      precondition(CloudAIService.gate.calls.isEmpty, "Empty source made a billable request")
    }
    for mode in [SummaryProcessingMode.balanced, .fast, .accurate] {
      let gate = SummaryFixtureGate()
      CloudAIService.gate = gate
      let input = makeInput(mode: mode)
      let work = Task { await MeetingSummarizer.summarize(input, engine: .cloud,
        llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in }) }
      let width = mode == .fast ? 2 : 1
      var virtualSeconds = 0
      for batch in 0..<(4 / width) {
        await wait { gate.pending.count == width }
        let calls = gate.pending.keys.sorted()
        precondition(gate.calls.count == (batch + 1) * width)
        virtualSeconds += 30
        for call in calls.reversed() {
          let part = input.transcript.firstIndex { gate.calls[call].user.contains($0.id.uuidString) }!
          gate.finish(call, .answer("根拠メモ\(part)"))
        }
      }
      await wait { gate.pending.count == 1 }
      precondition(gate.calls.count == 5 && gate.calls.allSatisfy { $0.mode == mode })
      let merge = gate.calls[4].user
      var previous = merge.startIndex
      for index in 0..<4 {
        guard let range = merge.range(of: "根拠メモ\(index)", range: previous..<merge.endIndex) else {
          throw NSError(domain: "SummaryPipelineChecks.order", code: index)
        }
        previous = range.upperBound
        precondition(gate.calls.prefix(4).contains { $0.user.contains(input.transcript[index].id.uuidString) })
      }
      precondition(!merge.contains(input.transcript[0].text), "Merge resent the full transcript")
      virtualSeconds += 60
      gate.finish(4, .answer("## 要約\n承認前は公開しない。150万円、期限は未定。"))
      guard case .success(let summary) = await work.value else { throw NSError(domain: "SummaryPipelineChecks.result", code: 1) }
      precondition(summary.markdown.contains("150万円") && gate.maximumActive == width)
      print("Summary pipeline virtual latency mode=\(mode.rawValue) parts=4 part=30s merge=60s total=\(virtualSeconds)s width=\(width); no API, not model quality")
    }
    for cancelled in [false, true] {
      let gate = SummaryFixtureGate()
      CloudAIService.gate = gate
      let work = Task { await MeetingSummarizer.summarize(makeInput(mode: .fast), engine: .cloud,
        llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in }) }
      await wait { gate.pending.count == 2 }
      if cancelled { work.cancel() } else { gate.finish(0, .failure(.providerUnavailable)) }
      let result = await work.value
      guard case .failure(let failure) = result else { throw NSError(domain: "SummaryPipelineChecks.partial", code: 1) }
      precondition(failure == (cancelled ? .cancelled : .providerUnavailable))
      precondition(gate.calls.count == 2 && gate.pending.isEmpty, "Failure submitted more parts or a merge")
    }
    let gate = SummaryFixtureGate()
    CloudAIService.gate = gate
    var allowed = true
    var work: Task<Result<MeetingSummary, AIAnswerFailure>, Never>!
    work = Task { await MeetingSummarizer.summarize(makeInput(mode: .fast), engine: .cloud,
      llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in if !allowed { work.cancel() } }) }
    await wait { gate.pending.count == 2 }
    allowed = false
    gate.finish(0, .answer("部分結果"))
    guard case .failure = await work.value else { throw NSError(domain: "SummaryPipelineChecks.revoked", code: 1) }
    precondition(gate.calls.count == 2 && gate.pending.isEmpty)
    print("SummaryPipelineChecks: PASS; actual split/ordered merge/parser, bounded concurrency, partial failure, cancellation and revoked progress boundary. Virtual timings are scheduling proof only.")
  }

  static func makeInput(mode: SummaryProcessingMode) -> MeetingSummaryInput {
    MeetingSummaryInput(title: "合成記録", date: .distantPast, duration: 7_200, participantNames: [],
      transcript: (0..<4).map { index in TranscriptSegment(id: UUID(), speaker: "話者\(index)", speakerIsCertain: false,
        timestamp: Double(index * 1_800), text: String(repeating: "原文の条件と否定・150万円を保持。", count: 1_500)) },
      template: .standard, preferences: SummaryPreferences(processingMode: mode))
  }

  static func wait(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() { precondition(ContinuousClock.now < deadline, "Fixture stalled"); await Task.yield() }
  }
}

@MainActor final class SummaryFixtureGate {
  struct Call { var user: String; var mode: SummaryProcessingMode }
  var calls: [Call] = []
  var pending: [Int: CheckedContinuation<AIAnswerResult, Never>] = [:]
  var maximumActive = 0
  func request(user: String, mode: SummaryProcessingMode) async -> AIAnswerResult {
    guard !Task.isCancelled else { return .failure(.cancelled) }
    let index = calls.count
    calls.append(Call(user: user, mode: mode))
    return await withTaskCancellationHandler {
      await withCheckedContinuation { pending[index] = $0; maximumActive = max(maximumActive, pending.count) }
    } onCancel: {
      Task { @MainActor in self.finish(index, .failure(.cancelled)) }
    }
  }
  func finish(_ index: Int, _ result: AIAnswerResult) { pending.removeValue(forKey: index)?.resume(returning: result) }
}

@MainActor enum CloudAIService {
  static var gate = SummaryFixtureGate()
  static func completeStreaming(system: String, user: String, llm: LLMSelection,
    processingMode: SummaryProcessingMode = .balanced,
    authorize: (@MainActor () -> Bool)? = nil,
    onActivity: (@MainActor () -> Void)? = nil, onProgress: @escaping @MainActor (Int) -> Void) async -> AIAnswerResult {
    if let authorize, !authorize() { return .failure(.cancelled) }
    return await gate.request(user: user, mode: processingMode)
  }
}
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
enum OnDeviceSummarizer {
  static func summarize(_ input: MeetingSummaryInput, progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> { .failure(.noEngine) }
}
