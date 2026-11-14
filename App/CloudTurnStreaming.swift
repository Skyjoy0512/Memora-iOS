import Foundation

enum CloudTurnStreaming {
  enum RequestEncoding { case configureStream, streamAlreadyConfigured }
  @MainActor
  static func response(for original: URLRequest, provider: CloudStreamAccumulator.Provider,
                       onText: @escaping @MainActor (String) -> Void,
                       sessionConfiguration: URLSessionConfiguration = .ephemeral, transport: CloudHTTPTransport? = nil,
                       onActivity: (@MainActor () -> Void)? = nil,
                       responseKind: CloudStreamAccumulator.ResponseKind = .agentTurn,
                       encoding: RequestEncoding = .configureStream) async throws -> [String: Any] {
    try await SummaryDiagnostics.$requestID.withValue(UUID()) {
      do {
        return try await performResponse(for: original, provider: provider, onText: onText,
          sessionConfiguration: sessionConfiguration, transport: transport, onActivity: onActivity, responseKind: responseKind, encoding: encoding)
      } catch {
        SummaryDiagnostics.current?.responseFailed(cancelled: Task.isCancelled || error is CancellationError ||
          (error as? AIAnswerFailure) == .cancelled || (error as? URLError)?.code == .cancelled)
        throw error
      }
    }
  }

  @MainActor
  private static func performResponse(for original: URLRequest, provider: CloudStreamAccumulator.Provider,
                       onText: @escaping @MainActor (String) -> Void, sessionConfiguration: URLSessionConfiguration, transport: CloudHTTPTransport?,
                       onActivity: (@MainActor () -> Void)?, responseKind: CloudStreamAccumulator.ResponseKind,
                       encoding: RequestEncoding) async throws -> [String: Any] {
    var request = encoding == .streamAlreadyConfigured ? original : try await configureStream(original)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    guard let endpoint = request.url else { throw AIAnswerFailure.network }
    let receiver = transport ?? CloudHTTPTransport(endpoint: endpoint, configuration: sessionConfiguration)
    defer { if transport == nil { receiver.invalidate() } }
    let (bytes, response) = try await receiver.bytes(for: request)
    SummaryDiagnostics.current?.record(.httpResponse, code: (response as? HTTPURLResponse)?.statusCode)
    try CloudAIService.validate(response)
    // Some compatible servers ignore stream. Accept that one response without
    // issuing a second paid request or replaying tools.
    if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true {
      let object = try await CloudTurnStreamReader.jsonResponse(from: bytes)
      let finish = provider == .anthropic ? object["stop_reason"] as? String :
        (object["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String
      SummaryDiagnostics.current?.providerStopped(finish)
      try validate(object, provider: provider, responseKind: responseKind)
      SummaryDiagnostics.current?.receivedUsage(object, usesAnthropicAPI: provider == .anthropic)
      SummaryDiagnostics.current?.outputReceived()
      SummaryDiagnostics.current?.responseCompleted()
      return object
    }
    return try await CloudTurnStreamReader.response(from: bytes, provider: provider, responseKind: responseKind,
      onActivity: onActivity, onText: onText)
  }

  @concurrent
  private static func configureStream(_ original: URLRequest) async throws -> URLRequest {
    var request = original
    guard let data = request.httpBody,
          var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
    body["stream"] = true
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  private static func validate(_ object: [String: Any], provider: CloudStreamAccumulator.Provider,
    responseKind: CloudStreamAccumulator.ResponseKind) throws {
    if responseKind == .textCompletion { _ = try CloudSummaryResponse(object, provider: provider) }
    else if provider == .anthropic { _ = try CloudAgentTurnDecoder.anthropic(object) }
    else { _ = try CloudAgentTurnDecoder.chatCompletions(object) }
  }
}
