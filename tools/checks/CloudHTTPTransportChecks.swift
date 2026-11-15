import Foundation

@MainActor enum CloudHTTPTransportChecks {
  static func run() async throws {
    typealias Wire = CloudSessionFixtureProtocol
    typealias Response = CloudSessionFixtureResponse
    let llm = LLMSelection(provider: .openAI, modelID: "gpt-6-sol")
    let endpoint = llm.baseURL.appendingPathComponent("chat/completions")
    let configuration = CloudSessionChecks.configuration()
    configuration.httpAdditionalHeaders = ["Cookie": "must-not-leave", "Authorization": "must-not-override"]
    let transport = CloudHTTPTransport(endpoint: endpoint, configuration: configuration)
    defer { transport.invalidate() }
    let diagnostic = SummaryDiagnostics(jobID: UUID(), engine: "cloud", provider: "fixture", model: "fixture", characters: 1, segments: 1)
    Wire.state.reset(try [Response.sse(provider: .openAI, text: "前半", finish: "length"),
                         Response.sse(provider: .openAI, text: "後半"),
                         Response.json(provider: .openAI, text: "次の区間")])
    await SummaryDiagnostics.$current.withValue(diagnostic) {
      let continued = await CloudAIService.completeStreaming(system: "架空", user: "架空", llm: llm,
        sessionConfiguration: configuration, admission: SummaryRequestAdmission(), transport: transport, onProgress: { _ in })
      precondition(continued.text == "前半後半" && continued.failure == nil)
      let next = await CloudAIService.completeStreaming(system: "架空", user: "架空", llm: llm,
        sessionConfiguration: configuration, admission: SummaryRequestAdmission(), transport: transport, onProgress: { _ in })
      precondition(next.text == "次の区間" && next.failure == nil)
    }
    Wire.state.assertConsumed(3)
    precondition(diagnostic.metrics.requestCount == 3 && diagnostic.metrics.continuations == 1)
    precondition(diagnostic.metrics.requests.count == 3 && diagnostic.metrics.requests.allSatisfy { $0.outcome == .completed })
    precondition(!diagnostic.metrics.measurementsIncomplete)
    precondition(diagnostic.events.filter { $0.stage == .sessionReuse }.map(\.code) == [0, 1, 1])
    precondition(Wire.state.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
    precondition(Wire.state.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer offline-fixture-key" })
    precondition(configuration.httpAdditionalHeaders?["Cookie"] as? String == "must-not-leave", "Caller configuration was mutated")
    precondition(Wire.state.requests.allSatisfy { request in
      let body = try? CloudSessionChecks.body(request)
      return ((body?["stream_options"] as? [String: Any])?["include_usage"] as? Bool) == true && body?["reasoning_effort"] == nil
    })

    var changed = Wire.state.requests[0]
    changed.setValue("Bearer other-account", forHTTPHeaderField: "Authorization")
    do { _ = try await transport.bytes(for: changed); preconditionFailure("Credential change reused a transport") }
    catch AIAnswerFailure.cancelled {}
    changed = Wire.state.requests[0]
    changed.url = URL(string: "https://other.invalid/chat/completions")!
    do { _ = try await transport.bytes(for: changed); preconditionFailure("Endpoint changed") }
    catch AIAnswerFailure.cancelled {}
    changed = Wire.state.requests[0]
    changed.setValue("manual-cookie", forHTTPHeaderField: "Cookie")
    do { _ = try await transport.bytes(for: changed); preconditionFailure("Explicit cookie escaped") }
    catch AIAnswerFailure.cancelled {}
    transport.invalidate()
    do { _ = try await transport.bytes(for: Wire.state.requests[0]); preconditionFailure("Closed transport sent") }
    catch AIAnswerFailure.cancelled {}
    Wire.state.assertConsumed(3)
    Wire.state.reset([.init(data: Data("{}".utf8), status: 429)])
    await SummaryDiagnostics.$current.withValue(diagnostic) {
      let limited = await CloudAIService.completeStreaming(system: "fixture", user: "fixture", llm: llm,
        sessionConfiguration: configuration, admission: SummaryRequestAdmission(), onProgress: { _ in })
      precondition(limited.failure == .rateLimited)
    }
    Wire.state.assertConsumed(1)
    precondition(diagnostic.metrics.requestCount == 4 && diagnostic.metrics.requests.filter { $0.outcome == .failed }.count == 1)
    print("CloudHTTPTransportChecks: PASS; same-session continuation/parts, copied config, cookie/credential/endpoint isolation, close and zero additional rejected dispatches; real TCP/TLS performance not measured")
  }
}
