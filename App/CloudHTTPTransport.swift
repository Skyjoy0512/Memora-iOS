import CryptoKit
import Foundation

/// One inference job owns one connection pool. Credentials are request headers,
/// never shared URLSession storage; a changed identity needs a new job.
final class CloudHTTPTransport: @unchecked Sendable {
  private let endpoint: URL
  private let session: URLSession
  private let summaryConcurrency: Int?
  private let admission: SummaryRequestAdmission
  private let lock = NSLock()
  private var identity: Data?
  private var closed = false
  private var requests = 0

  init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral,
    summaryConcurrency: Int? = nil, admission: SummaryRequestAdmission = .shared) {
    self.endpoint = endpoint
    self.summaryConcurrency = summaryConcurrency
    self.admission = admission
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

  func admit(_ request: URLRequest) async throws -> SummaryRequestAdmission.Permit? {
    guard let summaryConcurrency else { return nil }
    _ = try bind(request, countRequest: false)
    let fields = [endpoint.absoluteString, request.value(forHTTPHeaderField: "Authorization") ?? "",
      request.value(forHTTPHeaderField: "x-api-key") ?? ""]
    let key = SHA256.hash(data: try JSONEncoder().encode(fields)).map { String(format: "%02x", $0) }.joined()
    return try await admission.acquire(scope: key, maximumConcurrent: summaryConcurrency)
  }

  func release(_ permit: SummaryRequestAdmission.Permit?) async {
    if let permit { await admission.release(permit) }
  }

  func observe(_ response: URLResponse, permit: SummaryRequestAdmission.Permit?) async {
    if let permit, let http = response as? HTTPURLResponse, http.statusCode == 429 {
      await admission.rateLimited(permit, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
  }

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

  private func bind(_ request: URLRequest, countRequest: Bool = true) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !closed, request.url == endpoint,
          request.value(forHTTPHeaderField: "Cookie") == nil else { throw AIAnswerFailure.cancelled }
    let headers = [request.value(forHTTPHeaderField: "Authorization") ?? "",
      request.value(forHTTPHeaderField: "x-api-key") ?? ""]
    let encoded = try JSONEncoder().encode(headers)
    let fingerprint = Data(SHA256.hash(data: encoded))
    if let identity, identity != fingerprint { throw AIAnswerFailure.cancelled }
    identity = fingerprint
    defer { if countRequest { requests += 1 } }
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
