import Foundation

/// Wall-clock tests of the real URLSession bytes path. All URLs are intercepted;
/// no credential store, inference engine or remote service is consulted here.
@MainActor
enum SlowSummaryHTTPChecks {
  static func run() async throws {
    let cases = [(30, 0), (60, 0), (120, 0), (180, 0), (120, 60), (180, 60)]
    let work = cases.map { duration, firstToken in
      Task { @MainActor in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowSummaryProtocol.self]
        var request = URLRequest(url: URL(string: "https://offline.invalid/\(duration)/\(firstToken)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.httpBody = Data("{\"model\":\"fixture\",\"messages\":[]}".utf8)
        let start = ContinuousClock.now
        var firstArrival: Double?
        let response = try await CloudTurnStreaming.response(for: request, provider: .chatCompletions,
          onText: { _ in
            if firstArrival == nil { firstArrival = seconds(start.duration(to: .now)) }
          }, sessionConfiguration: configuration, responseKind: .textCompletion)
        let elapsed = seconds(start.duration(to: .now))
        let result = try CloudSummaryResponse(response, provider: .chatCompletions)
        precondition(result.text == "前半後半" && !result.wasCutOff)
        precondition(elapsed >= Double(duration) - 0.5 && elapsed < Double(duration) + 30)
        precondition(firstArrival != nil && firstArrival! >= Double(firstToken) - 0.5)
        print(String(format: "Wall-clock URLSession duration=%ds firstToken=%ds actual=%.3fs first=%.3fs: PASS", duration, firstToken, elapsed, firstArrival!))
      }
    }
    for test in work { try await test.value }
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}

private final class SlowSummaryProtocol: URLProtocol, @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private var stopped = false
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url, url.host == "offline.invalid",
          url.pathComponents.count == 3, let duration = Double(url.pathComponents[1]),
          let first = Double(url.pathComponents[2]), duration <= 180 else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200,
      httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
    DispatchQueue.global().asyncAfter(deadline: .now() + first) { self.emit("data: {\"choices\":[{\"delta\":{\"content\":\"前半\"}}]}\n\n", finished: false) }
    DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
      self.emit("data: {\"choices\":[{\"delta\":{\"content\":\"後半\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n", finished: true)
    }
  }
  override func stopLoading() { lock.lock(); defer { lock.unlock() }; stopped = true }
  private func emit(_ text: String, finished: Bool) {
    lock.lock(); defer { lock.unlock() }
    guard !stopped else { return }
    client?.urlProtocol(self, didLoad: Data(text.utf8))
    if finished { client?.urlProtocolDidFinishLoading(self) }
  }
}
