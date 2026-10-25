import Foundation

enum CloudTurnStreaming {
  @MainActor
  static func response(for original: URLRequest, provider: CloudStreamAccumulator.Provider,
                       onText: @escaping @MainActor (String) -> Void,
                       sessionConfiguration: URLSessionConfiguration = .ephemeral,
                       onActivity: (@MainActor () -> Void)? = nil,
                       responseKind: CloudStreamAccumulator.ResponseKind = .agentTurn) async throws -> [String: Any] {
    var request = original
    guard let data = request.httpBody,
          var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
    body["stream"] = true
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    sessionConfiguration.timeoutIntervalForResource = 600
    let session = URLSession(configuration: sessionConfiguration)
    defer { session.invalidateAndCancel() }
    SummaryDiagnostics.current?.record(.request)
    let (bytes, response) = try await session.bytes(for: request)
    SummaryDiagnostics.current?.record(.httpResponse, code: (response as? HTTPURLResponse)?.statusCode)
    try CloudAIService.validate(response)
    // Some compatible servers ignore stream. Accept that one response without
    // issuing a second paid request or replaying tools.
    if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true {
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < AgentSessionBudget.maximumResponseBytes else { throw AIAnswerFailure.executionLimit }
        data.append(byte)
      }
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
      try validate(object, provider: provider, responseKind: responseKind)
      SummaryDiagnostics.current?.outputReceived()
      SummaryDiagnostics.current?.responseCompleted()
      return object
    }
    return try await CloudTurnStreamReader.response(from: bytes, provider: provider, responseKind: responseKind,
      onActivity: onActivity, onText: onText)
  }

  private static func validate(_ object: [String: Any], provider: CloudStreamAccumulator.Provider,
    responseKind: CloudStreamAccumulator.ResponseKind) throws {
    if responseKind == .textCompletion { _ = try CloudSummaryResponse(object, provider: provider) }
    else if provider == .anthropic { _ = try CloudAgentTurnDecoder.anthropic(object) }
    else { _ = try CloudAgentTurnDecoder.chatCompletions(object) }
  }
}
