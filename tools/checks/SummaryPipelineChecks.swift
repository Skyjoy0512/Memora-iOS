import Foundation

/// Production orchestration and parser; only provider/OS inference is replaced.
@main @MainActor
enum SummaryPipelineChecks {
  static func main() async throws {
    try await cacheChecks()
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
    // Even an off-contract video reply cannot turn viewer advice into tasks or meeting decisions.
    let videoGate = SummaryFixtureGate()
    CloudAIService.gate = videoGate
    let videoInput = MeetingSummaryInput(title: "字幕だけの動画", date: .now, duration: 0,
      participantNames: [], transcript: [TranscriptSegment(id: UUID(), speaker: "字幕", speakerIsCertain: false,
        timestamp: 0, text: "今回の動画では条件付きの方法を説明します。")], template: .market(VideoSummaryTemplate.template))
    let videoWork = Task { await MeetingSummarizer.summarize(videoInput, engine: .cloud,
      llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in }) }
    await wait { videoGate.pending.count == 1 }
    precondition(videoGate.calls[0].user.contains("[時刻不明]"))
    videoGate.finish(0, .answer("## 重要なポイント\n条件付きの方法。\n<memora-data>{\"templateID\":\"content.video\",\"decisions\":[\"登録する\"],\"actions\":[{\"title\":\"登録する\"}]}</memora-data>"))
    guard case .success(let videoResult) = await videoWork.value else { preconditionFailure("video summary failed") }
    precondition(videoResult.actions.isEmpty && videoResult.decisions.isEmpty && videoResult.templateID == "content.video")
    for modelID in ["unknown-custom", "gpt-6-sol"] {
      let singleGate = SummaryFixtureGate()
      CloudAIService.gate = singleGate
      var singleInput = makeInput(mode: .accurate)
      let count = modelID == "unknown-custom" ? 1 : 1000
      singleInput.transcript = (0..<count).map { index in
        TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: Double(index),
          text: "発言\(index)：公開決定は撤回しました。監査承認と性能試験が終わるまで公開しません。金額は150万円です。")
      }
      let singleWork = Task { await MeetingSummarizer.summarize(singleInput, engine: .cloud,
        llm: LLMSelection(provider: .openAI, modelID: modelID), progress: { _ in }) }
      await wait { singleGate.pending.count == 1 }
      precondition(singleGate.calls[0].user.contains("# 抽出データ"))
      precondition(singleGate.calls[0].user.contains(singleInput.transcript.last!.text))
      precondition(singleGate.calls[0].user.contains(singleInput.transcript.first!.text))
      singleGate.finish(0, .answer("## 公開条件\n監査承認と性能試験が終わるまで公開しません。"))
      guard case .success = await singleWork.value else { preconditionFailure("Single pass failed") }
      precondition(singleGate.calls.count == 1)
      print("Capacity route: \(modelID) utterances=\(count), actual mock requests=1; all source preserved, not real-model performance")
    }
        let proofGate = SummaryFixtureGate()
    CloudAIService.gate = proofGate
    var proofInput = makeInput(mode: .balanced)
    proofInput.transcript = (0..<40).map { index in
      TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false, timestamp: Double(index),
        text: "負荷試験の完了までは公開しません。条件と否定を保持します。")
    }
    let proofWork = Task { await MeetingSummarizer.summarize(proofInput, engine: .cloud,
      llm: LLMSelection(provider: .openAI, modelID: "gpt-6-sol"), progress: { _ in }) }
    await wait { proofGate.pending.count == 1 }
    precondition(proofGate.calls[0].user.contains("# 抽出データ"), "Fixture expects a single-pass route")
    precondition(proofGate.calls[0].user.contains("S3 A1:"))
    precondition(!proofGate.calls[0].user.contains(proofInput.transcript[2].id.uuidString))
    proofGate.finish(0, .answer("""
    ## 負荷試験後の公開
    負荷試験の完了までは公開しません。
    <memora-data>{"templateID":"builtin.detailedOverview","sourceReferences":[{"sectionTitle":"負荷試験後の公開","sourceSegmentID":"S3","quote":"負荷試験の完了までは公開しません。"}],"knowledge":{"facts":[{"id":"f1","category":"constraint","status":"confirmed","content":"試験完了前は公開しない","sourceReferences":[{"sourceSegmentID":"S3","quote":"負荷試験の完了までは公開しません。"}]}]}}</memora-data>
    """))
    guard case .success(let proofSummary) = await proofWork.value else { preconditionFailure("proof summary failed") }
    precondition(proofSummary.evidence.first?.sourceSegmentID == proofInput.transcript[2].id.uuidString)
    precondition(proofSummary.knowledge?.facts.first?.sourceReferences?.first?.sourceSegmentID == proofInput.transcript[2].id.uuidString)
        for mode in [SummaryProcessingMode.balanced, .fast, .accurate] {
      let gate = SummaryFixtureGate()
      CloudAIService.gate = gate
      let input = makeInput(mode: mode)
      let work = Task { await MeetingSummarizer.summarize(input, engine: .cloud,
        llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in }) }
      let width = SummaryGenerationPolicy.parallelParts(mode, llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"))
      var virtualSeconds = 0
      for batch in 0..<(4 / width) {
        await wait { gate.pending.count == width }
        let calls = gate.pending.keys.sorted()
        precondition(gate.calls.count == (batch + 1) * width)
        virtualSeconds += 30
        for call in calls.reversed() {
          let part = input.transcript.enumerated().first { entry in
            gate.calls[call].user.contains(entry.element.id.uuidString) ||
              gate.calls[call].user.contains("S\(entry.offset + 1) A")
          }!.offset
          gate.finish(call, .answer("根拠メモ\(part)"))
        }
      }
      await wait { gate.pending.count == 1 }
      precondition(gate.calls.count == 5 && gate.calls.allSatisfy { $0.mode == mode })
      precondition(gate.calls.compactMap(\.transportID).count == 5 && Set(gate.calls.compactMap(\.transportID)).count == 1,
        "Parts and final request did not share their scoped transport")
      let merge = gate.calls[4].user
      var previous = merge.startIndex
      for index in 0..<4 {
        guard let range = merge.range(of: "根拠メモ\(index)", range: previous..<merge.endIndex) else {
          throw NSError(domain: "SummaryPipelineChecks.order", code: index)
        }
        previous = range.upperBound
        precondition(gate.calls.prefix(4).contains { $0.user.contains("S\(index + 1) A") || $0.user.contains(input.transcript[index].id.uuidString) })
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
      await wait { gate.pending.count == SummaryGenerationPolicy.parallelParts(.fast, llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")) }
      if cancelled { work.cancel() } else { gate.finish(0, .failure(.providerUnavailable)) }
      let result = await work.value
      guard case .failure(let failure) = result else { throw NSError(domain: "SummaryPipelineChecks.partial", code: 1) }
      precondition(failure == (cancelled ? .cancelled : .providerUnavailable))
      precondition(gate.calls.count == SummaryGenerationPolicy.parallelParts(.fast, llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")) && gate.pending.isEmpty, "Failure submitted more parts or a merge")
    }
    let gate = SummaryFixtureGate()
    CloudAIService.gate = gate
    var allowed = true
    var work: Task<Result<MeetingSummary, AIAnswerFailure>, Never>!
    work = Task { await MeetingSummarizer.summarize(makeInput(mode: .fast), engine: .cloud,
      llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro"), progress: { _ in if !allowed { work.cancel() } }) }
    await wait { gate.pending.count == SummaryGenerationPolicy.parallelParts(.fast, llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")) }
    allowed = false
    gate.finish(0, .answer("部分結果"))
    guard case .failure = await work.value else { throw NSError(domain: "SummaryPipelineChecks.revoked", code: 1) }
    precondition(gate.calls.count == SummaryGenerationPolicy.parallelParts(.fast, llm: LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")) && gate.pending.isEmpty)
    print("SummaryPipelineChecks: PASS; actual split/ordered merge/parser, bounded concurrency, partial failure, cancellation and revoked progress boundary. Virtual timings are scheduling proof only.")
  }

  static func makeInput(mode: SummaryProcessingMode) -> MeetingSummaryInput {
    MeetingSummaryInput(title: "合成記録", date: .distantPast, duration: 7_200, participantNames: [],
      transcript: (0..<4).map { index in TranscriptSegment(id: UUID(), speaker: "話者\(index)", speakerIsCertain: false,
        timestamp: Double(index * 1_800), text: String(repeating: "原文の条件と否定・150万円を保持。", count: 15_000)) },
      template: .standard, preferences: SummaryPreferences(processingMode: mode))
  }

  static func cacheChecks() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalStore(fileURL: directory.appendingPathComponent("cache.sqlite"))
    try store.prepare()
    let cache = SummaryArtifactCache(store: store)
    let llm = LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")
    var input = makeInput(mode: .accurate)
    input.artifactScope = .init(ownerID: UUID(), workspace: "personal", account: "synthetic-account",
      privacy: "synthetic-permission", credentialHash: "synthetic-key-hash")
    let identity = SummaryArtifactIdentity.identity(scope: input.artifactScope!, input: input, llm: llm)!
    precondition(SummaryArtifactIdentity.identity(scope: input.artifactScope!, input: input,
      llm: .init(provider: llm.provider, modelID: "different-model")) != identity)
    var changed = input
    changed.transcript[0].endTime = 42
    precondition(SummaryArtifactIdentity.identity(scope: input.artifactScope!, input: changed, llm: llm) != identity)
    changed = input
    changed.transcript[0].speaker = "訂正された話者"
    precondition(SummaryArtifactIdentity.identity(scope: input.artifactScope!, input: changed, llm: llm) != identity)
    for property in ["account", "workspace", "credential", "privacy", "owner"] {
      var scope = input.artifactScope!
      switch property {
      case "account": scope.account += "new"
      case "workspace": scope.workspace += "new"
      case "credential": scope.credentialHash += "new"
      case "privacy": scope.privacy += "new"
      default: scope.ownerID = UUID()
      }
      precondition(SummaryArtifactIdentity.identity(scope: scope, input: input, llm: llm) != identity)
    }
    for pass in 0..<2 {
      let gate = SummaryFixtureGate()
      CloudAIService.gate = gate
      let snapshot = input
      let work = Task { await MeetingSummarizer.summarize(snapshot, engine: .cloud, llm: llm,
        artifactCache: cache, authorize: { true }, progress: { _ in }) }
      if pass == 0 {
        var finished = 0
        while finished < 4 {
          await wait { !gate.pending.isEmpty }
          for call in gate.pending.keys.sorted() {
            let index = (0..<4).first { gate.calls[call].user.contains("S\($0 + 1) A") || gate.calls[call].user.contains(input.transcript[$0].id.uuidString) }!
            let compact = gate.calls[call].user.contains("S\(index + 1) A")
            let artifact = SummaryPartArtifact(notes: "区間\(index)では原文の条件と否定・150万円を保持。",
              sourceReferences: [.init(sourceSegmentID: compact ? "S\(index + 1)" : input.transcript[index].id.uuidString, quote: "原文の条件と否定・150万円を保持。")])
            let text = String(decoding: try JSONEncoder().encode(artifact), as: UTF8.self)
            precondition(artifact.validated(in: SummarySourceIndex(input.transcript),
              part: [SummarySourceIndex(input.transcript).units(hasTimestamps: true, compact: compact)[index].line], compact: compact))
            gate.finish(call, .answer(text))
            finished += 1
          }
        }
      }
      await wait { gate.pending.count == 1 }
      let last = gate.pending.keys.first!
      precondition(gate.calls.count == (pass == 0 ? 5 : 1))
      for index in 0..<4 { precondition(gate.calls[last].user.contains("区間\(index)")) }
      gate.finish(last, .answer("## 公開条件\n原文の条件と否定・150万円を保持。"))
      guard case .success = await work.value else { preconditionFailure("Cache path failed") }
      input.preferences.length = .detailed
      input.preferences.displayOrder = .chronological
    }
    let gate = SummaryFixtureGate()
    CloudAIService.gate = gate
    let denied = await MeetingSummarizer.summarize(input, engine: .cloud, llm: llm,
      artifactCache: cache, authorize: { false }, progress: { _ in })
    guard case .failure = denied else { preconditionFailure("Revoked access reused analysis") }
    precondition(gate.calls.isEmpty)
    let index = SummarySourceIndex(input.transcript)
    let forged = SummaryPartArtifact(notes: "未検証", sourceReferences: [.init(sourceSegmentID: "S99", quote: "原文の条件と否定・150万円を保持。")])
    precondition(!forged.validated(in: index, part: index.lines(hasTimestamps: true), compact: true))
    print("Cached regeneration: actual production orchestration mock requests 5 → 1 across length/order change, source/model/account/permission keys and revoked access checked; no API latency or semantic quality claim.")
  }

  static func wait(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() { precondition(ContinuousClock.now < deadline, "Fixture stalled"); await Task.yield() }
  }
}

@MainActor final class SummaryFixtureGate {
  struct Call { var user: String; var mode: SummaryProcessingMode; var transportID: ObjectIdentifier? }
  var calls: [Call] = []
  var pending: [Int: CheckedContinuation<AIAnswerResult, Never>] = [:]
  var maximumActive = 0
  func request(user: String, mode: SummaryProcessingMode, transport: CloudHTTPTransport?) async -> AIAnswerResult {
    guard !Task.isCancelled else { return .failure(.cancelled) }
    let index = calls.count
    calls.append(Call(user: user, mode: mode, transportID: transport.map(ObjectIdentifier.init)))
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
    transport: CloudHTTPTransport? = nil, processingMode: SummaryProcessingMode = .balanced,
    authorize: (@MainActor () -> Bool)? = nil,
    onActivity: (@MainActor () -> Void)? = nil, onProgress: @escaping @MainActor (Int) -> Void) async -> AIAnswerResult {
    if let authorize, !authorize() { return .failure(.cancelled) }
    return await gate.request(user: user, mode: processingMode, transport: transport)
  }
}
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
enum OnDeviceSummarizer {
  static func summarize(_ input: MeetingSummaryInput, progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> { .failure(.noEngine) }
}
