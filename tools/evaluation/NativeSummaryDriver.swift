import Foundation

/// Provider bytes enter through the broker. Inference, credentials and network
/// permission stay outside this executable; the app's decoder sees the real SSE.
@main @MainActor
enum NativeSummaryDriver {
  struct Source: Decodable {
    var id: UUID
    var title: String
    var date: Date
    var duration: Double
    var participantNames: [String]
    var transcript: [TranscriptSegment]
    var preferences: SummaryPreferences
    var glossary: [String]?
    var sourceContext: String?
    var template: SummaryTemplateChoice?
  }
  struct Configuration: Decodable {
    var source: Source
    var llm: LLMSelection
    var options: NativeSummaryEvaluation.Options
    var database: URL
  }

  static func main() async throws {
    guard CommandLine.arguments.count == 2 else { throw AIAnswerFailure.executionLimit }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let config = try decoder.decode(Configuration.self, from: Data(contentsOf: URL(filePath: CommandLine.arguments[1])))
    guard config.database.isFileURL, (1...4).contains(config.options.concurrency),
          config.source.duration.isFinite, config.source.duration >= 0,
          !config.source.transcript.isEmpty, Set(config.source.transcript.map(\.id)).count == config.source.transcript.count else {
      throw AIAnswerFailure.executionLimit
    }
    // Never consult or update the developer's saved BYOK settings.
    UserDefaults.standard.setVolatileDomain([ModelCapabilityOverrides.defaultsKey: Data("{}".utf8)], forName: UserDefaults.argumentDomain)
    NativeSummaryWire.startReader()
    let store = LocalStore(fileURL: config.database)
    try store.prepare()
    let cache = SummaryArtifactCache(store: store)
    var input = MeetingSummaryInput(title: config.source.title, date: config.source.date,
      duration: config.source.duration, participantNames: config.source.participantNames,
      transcript: config.source.transcript, template: config.source.template ?? .standard, glossary: config.source.glossary ?? [],
      preferences: config.source.preferences, sourceContext: config.source.sourceContext)
    input.artifactScope = .init(ownerID: config.source.id, workspace: "evaluation", account: "evaluation",
      privacy: "manifest-bound", credentialHash: "evaluation-only")
    await NativeSummaryEvaluation.$options.withValue(config.options) {
      if config.options.variant == "cache-warm" {
        guard await run(input, llm: config.llm, cache: cache, store: store, phase: "warmup") else { return }
      }
      _ = await run(input, llm: config.llm, cache: cache, store: store, phase: "measured")
    }
  }

  static func run(_ input: MeetingSummaryInput, llm: LLMSelection, cache: SummaryArtifactCache,
                  store: LocalStore, phase: String) async -> Bool {
    let start = ContinuousClock.now
    let diagnostic = SummaryDiagnostics(jobID: UUID(), engine: "native-host", provider: llm.provider.rawValue,
      model: llm.modelID, characters: input.transcript.reduce(0) { $0 + $1.text.count }, segments: input.transcript.count)
    return await SummaryDiagnostics.$current.withValue(diagnostic) {
      NativeSummaryWire.emit(["kind": "phase", "phase": phase])
      let result = await MeetingSummarizer.summarize(input, engine: .cloud, llm: llm,
        artifactCache: cache, authorize: { !Task.isCancelled }, progress: { _ in })
      var event: [String: Any] = ["kind": "result", "phase": phase, "status": "failed",
        "persistenceBoundary": "host-summary-document", "measurementKind": "native-host-streaming",
        "automaticAdoption": false]
      do {
        switch result {
        case .failure(let failure): event["failure"] = String(describing: failure)
        case .success(let summary):
          diagnostic.record(.saveStarted)
          let bytes = try JSONEncoder().encode(NativeSummarySnapshot(summary))
          try store.write("evaluation-summary", data: bytes)
          diagnostic.record(.saveCompleted)
          guard case .data(let readback) = store.readOutcome("evaluation-summary"), readback == bytes else { throw AIAnswerFailure.generationFailed }
          event["summary"] = try JSONSerialization.jsonObject(with: bytes)
          event["status"] = "completed"
        }
      } catch { event["failure"] = "persistenceFailed" }
      let elapsed = start.duration(to: .now).components
      event["summarySeconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
      event["diagnostics"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(diagnostic.metrics))
      event["plannedParts"] = diagnostic.events.first { $0.stage == .plannedParts }?.code
      NativeSummaryWire.emit(event)
      return event["status"] as? String == "completed"
    }
  }
}
