import Foundation

enum CloudTurnStreaming {
  @MainActor
  static func response(for original: URLRequest, provider: CloudStreamAccumulator.Provider,
                       onText: @escaping @MainActor (String) -> Void) async throws -> [String: Any] {
    var request = original
    guard let data = request.httpBody,
          var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
    body["stream"] = true
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 600
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    try CloudAIService.validate(response)
    // Some compatible servers ignore stream. Accept that one response without
    // issuing a second paid request or replaying tools.
    if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true {
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < 2 * 1024 * 1024 else { throw AIAnswerFailure.server }
        data.append(byte)
      }
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
      return object
    }
    var accumulator = CloudStreamAccumulator(provider: provider)
    var eventLines: [String] = []
    var totalBytes = 0
    let clock = ContinuousClock()
    var lastPublication = clock.now
    var published = ""
    for try await line in bytes.lines {
      try Task.checkCancellation()
      totalBytes += line.utf8.count + 1
      guard totalBytes <= 2 * 1024 * 1024 else { throw AIAnswerFailure.server }
      if line.hasPrefix("data:") { eventLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
      if line.isEmpty, !eventLines.isEmpty {
        try accumulator.consume(eventLines.joined(separator: "\n"))
        eventLines.removeAll(keepingCapacity: true)
        let now = clock.now
        if accumulator.text != published, published.isEmpty || lastPublication.duration(to: now) >= .milliseconds(100) || accumulator.isFinished {
          published = accumulator.text
          lastPublication = now
          onText(published)
        }
        if accumulator.isFinished { break }
      }
    }
    if !eventLines.isEmpty { try accumulator.consume(eventLines.joined(separator: "\n")) }
    try Task.checkCancellation()
    let result = try accumulator.response()
    if accumulator.text != published { onText(accumulator.text) }
    return result
  }
}
