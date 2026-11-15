import Foundation
import Synchronization

@MainActor enum CloudSummaryAdmissionChecks {
  static func run() async throws {
    typealias Wire = CloudSessionFixtureProtocol
    let clock = Mutex(ContinuousClock.now)
    let admission = SummaryRequestAdmission(now: { clock.withLock { $0 } })
    let llm = LLMSelection(provider: .openAI, modelID: "gpt-6-sol")
    let endpoint = llm.baseURL.appendingPathComponent("chat/completions")
    let transport = CloudHTTPTransport(endpoint: endpoint, configuration: CloudSessionChecks.configuration(),
      summaryConcurrency: 1, admission: admission)
    defer { transport.invalidate() }
    var request = URLRequest(url: endpoint)
    request.setValue("Bearer offline-fixture-key", forHTTPHeaderField: "Authorization")
    let blocker = try await transport.admit(request)
    var allowed = true
    Wire.state.reset([])
    let stale = Task { await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
      transport: transport, authorize: { allowed }, onProgress: { _ in }) }
    await queued(admission)
    allowed = false
    await transport.release(blocker)
    let denied = await stale.value
    precondition(denied.failure == .contextChanged)
    Wire.state.assertConsumed(0)

    let occupied = try await transport.admit(request)
    let cancelled = Task { await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
      transport: transport, onProgress: { _ in }) }
    await queued(admission)
    cancelled.cancel()
    let stopped = await cancelled.value
    precondition(stopped.failure == .cancelled)
    await transport.release(occupied)
    Wire.state.assertConsumed(0)

    for streaming in [false, true] {
      let occupied = try await transport.admit(request)
      var authorized = true
      let agent = CloudAgentSession(llm: llm, system: "fixture", tools: [],
        sessionConfiguration: CloudSessionChecks.configuration(), admission: admission,
        authorize: { authorized })!
      agent.addUserMessage("fixture")
      let pending = Task<AgentTurn, Error> {
        if streaming { return try await agent.next { _ in } }
        return try await agent.next()
      }
      await queued(admission)
      authorized = false
      await transport.release(occupied)
      do { _ = try await pending.value; preconditionFailure("Queued agent sent revoked context") }
      catch AIAnswerFailure.contextChanged {}
      Wire.state.assertConsumed(0)
    }

    let occupiedCompletion = try await transport.admit(request)
    var completionAllowed = true
    let completion = Task { await CloudAIService.complete(system: "fixture", user: "fixture", llm: llm,
      maximumOutputTokens: 100, sessionConfiguration: CloudSessionChecks.configuration(), admission: admission,
      authorize: { completionAllowed }) }
    await queued(admission)
    completionAllowed = false
    await transport.release(occupiedCompletion)
    let completionResult = await completion.value
    precondition(completionResult.failure == .contextChanged)
    Wire.state.assertConsumed(0)

    let anotherJob = CloudHTTPTransport(endpoint: endpoint, configuration: CloudSessionChecks.configuration(),
      summaryConcurrency: 1, admission: admission)
    defer { anotherJob.invalidate() }
    var stream = try CloudSessionFixtureResponse.sse(provider: .openAI, text: "本文を受信")
    stream.isBodySuspended = true
    Wire.state.reset(try [stream, CloudSessionFixtureResponse.json(provider: .openAI, text: "別のジョブ")])
    let reading = Task { await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
      transport: transport, onProgress: { _ in }) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !Wire.state.isSuspended {
      precondition(ContinuousClock.now < deadline)
      await Task.yield()
    }
    let waiting = Task { await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
      transport: anotherJob, onProgress: { _ in }) }
    await queued(admission)
    precondition(Wire.state.requests.count == 1, "Released global slot at HTTP headers before receiving body")
    Wire.state.release()
    let read = await reading.value, next = await waiting.value
    precondition(read.text == "本文を受信" && next.text == "別のジョブ")
    Wire.state.assertConsumed(2)

    Wire.state.reset([.init(data: Data(), status: 429, retryAfter: "120")])
    let diagnostics = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "fixture", model: "fixture", characters: 1, segments: 1)
    await SummaryDiagnostics.$current.withValue(diagnostics) {
      for _ in 0..<2 {
        let rejected = await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
          transport: transport, onProgress: { _ in })
        precondition(rejected.failure == .rateLimited)
      }
    }
    Wire.state.assertConsumed(1)
    precondition(diagnostics.metrics.requestCount == 1, "A local rejection was recorded as a sent request")
    clock.withLock { $0 = $0.advanced(by: .seconds(121)) }
    Wire.state.reset(try [CloudSessionFixtureResponse.json(provider: .openAI, text: "完了")])
    let finished = await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
      transport: transport, onProgress: { _ in })
    precondition(finished.text == "完了")
    Wire.state.assertConsumed(1)
    let counts = await admission.counts
    precondition(counts.active == 0 && counts.waiting == 0)
    print("CloudSummaryAdmissionChecks: PASS; production HTTP path reauthorizes after queue, cancels with zero dispatches, shares 429/Retry-After with one actual request and recovers with virtual time; no model/network.")
  }

  private static func queued(_ admission: SummaryRequestAdmission) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await admission.counts.waiting != 1 {
      precondition(ContinuousClock.now < deadline)
      await Task.yield()
    }
  }
}
