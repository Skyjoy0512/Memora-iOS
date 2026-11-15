import Foundation

/// Installed only on the runner's ephemeral sessions. Every URL is intercepted;
/// an exhausted script fails closed instead of falling through to the network.
final class CloudSessionFixtureProtocol: URLProtocol, @unchecked Sendable {
  static let state = State()
  private let deliveryLock = NSRecursiveLock()
  private var stopped = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let reply = Self.state.take(request) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    if reply.isSuspended { Self.state.suspend(self, reply: reply) }
    else { deliver(reply) }
  }

  override func stopLoading() {
    deliveryLock.lock(); defer { deliveryLock.unlock() }
    stopped = true
    Self.state.didStop(self)
  }

  func deliver(_ reply: Reply, headersAlreadySent: Bool = false) {
    deliveryLock.lock(); defer { deliveryLock.unlock() }
    guard !stopped else { return }
    if let error = reply.error {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }
    var headers = ["Content-Type": reply.contentType]
    if let retryAfter = reply.retryAfter { headers["Retry-After"] = retryAfter }
    let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
    if !headersAlreadySent { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
    if reply.isBodySuspended && !headersAlreadySent {
      Self.state.suspend(self, reply: reply, headersAlreadySent: true)
      return
    }
    var offset = 0
    while offset < reply.data.count {
      let end = min(offset + reply.chunkSize, reply.data.count)
      client?.urlProtocol(self, didLoad: reply.data.subdata(in: offset..<end))
      offset = end
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  struct Reply {
    var data: Data
    var contentType = "application/json"
    var status = 200
    var chunkSize = 31
    var error: URLError?
    var isSuspended = false
    var retryAfter: String?
    var isBodySuspended = false
  }

  final class State: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Reply] = []
    private var captured: [URLRequest] = []
    private var pending: (CloudSessionFixtureProtocol, Reply, Bool)?
    private var stoppedCount = 0
    private var unexpected = 0

    func reset(_ replies: [Reply]) {
      lock.lock(); defer { lock.unlock() }
      precondition(pending == nil)
      self.replies = replies; captured = []; stoppedCount = 0; unexpected = 0
    }
    func take(_ request: URLRequest) -> Reply? {
      lock.lock(); defer { lock.unlock() }
      var request = request
      if request.httpBody == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var body = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
          let count = stream.read(&buffer, maxLength: buffer.count)
          precondition(count >= 0 && body.count <= AgentSessionBudget.maximumRequestBytes)
          if count == 0 { break }
          body.append(contentsOf: buffer.prefix(count))
        }
        request.httpBody = body
      }
      captured.append(request)
      guard !replies.isEmpty else { unexpected += 1; return nil }
      return replies.removeFirst()
    }
    func suspend(_ connection: CloudSessionFixtureProtocol, reply: Reply, headersAlreadySent: Bool = false) {
      lock.lock(); defer { lock.unlock() }
      precondition(pending == nil)
      pending = (connection, reply, headersAlreadySent)
    }
    func release() {
      lock.lock(); let value = pending; pending = nil; lock.unlock()
      if let (connection, reply, headersAlreadySent) = value { connection.deliver(reply, headersAlreadySent: headersAlreadySent) }
    }
    func didStop(_ connection: CloudSessionFixtureProtocol) {
      lock.lock(); defer { lock.unlock() }
      stoppedCount += 1
      if pending?.0 === connection { pending = nil }
    }
    var requests: [URLRequest] {
      lock.lock(); defer { lock.unlock() }; return captured
    }
    var isSuspended: Bool {
      lock.lock(); defer { lock.unlock() }; return pending != nil
    }
    func assertConsumed(_ count: Int) {
      lock.lock(); defer { lock.unlock() }
      precondition(captured.count == count && replies.isEmpty && pending == nil && unexpected == 0,
        "expected=\(count) captured=\(captured.count) replies=\(replies.count) pending=\(pending != nil) unexpected=\(unexpected)")
    }
  }
}
