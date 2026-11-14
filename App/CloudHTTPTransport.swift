import CryptoKit
import Foundation

/// One inference job owns one connection pool. Credentials are request headers,
/// never shared URLSession storage; a changed identity needs a new job.
final class CloudHTTPTransport: @unchecked Sendable {
  private let endpoint: URL
  private let session: URLSession
  private let lock = NSLock()
  private var identity: Data?
  private var closed = false
  private var requests = 0

  init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral) {
    self.endpoint = endpoint
    let configuration = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
    configuration.timeoutIntervalForResource = 600
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    let privateHeaders = Set(["cookie", "authorization", "x-api-key"])
    configuration.httpAdditionalHeaders = configuration.httpAdditionalHeaders?.filter { key, _ in
      guard let name = key as? String else { return true }
      return !privateHeaders.contains(name.lowercased())
    }
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
  }

  deinit { session.invalidateAndCancel() }

  func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
    try Task.checkCancellation()
    let reused = try bind(request)
    try Task.checkCancellation()
    SummaryDiagnostics.current?.record(.sessionReuse, code: reused ? 1 : 0)
    SummaryDiagnostics.current?.record(.request)
    if SummaryDiagnostics.isContinuation { SummaryDiagnostics.current?.record(.continuation) }
    return try await session.bytes(for: request)
  }

  func invalidate() {
    lock.lock()
    closed = true
    lock.unlock()
    session.invalidateAndCancel()
  }

  private func bind(_ request: URLRequest) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !closed, request.url == endpoint,
          request.value(forHTTPHeaderField: "Cookie") == nil else { throw AIAnswerFailure.cancelled }
    let headers = [request.value(forHTTPHeaderField: "Authorization") ?? "",
      request.value(forHTTPHeaderField: "x-api-key") ?? ""]
    let encoded = try JSONEncoder().encode(headers)
    let fingerprint = Data(SHA256.hash(data: encoded))
    if let identity, identity != fingerprint { throw AIAnswerFailure.cancelled }
    identity = fingerprint
    defer { requests += 1 }
    return requests > 0
  }

  private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void) {
      // A model endpoint is explicit. Redirects must not forward source text or
      // credentials to a URL the person never selected.
      completionHandler(nil)
    }
  }
}
