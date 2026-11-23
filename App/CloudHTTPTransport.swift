import CryptoKit
import Foundation

/// One inference job owns one connection pool. Credentials are request headers,
/// never shared URLSession storage; a changed identity needs a new job.
final class CloudHTTPTransport: @unchecked Sendable {
  private let endpoint: URL
  private let session: URLSession
  private let summaryConcurrency: Int
  private let priority: SummaryRequestAdmission.Priority
  private let requestsPerMinute: Int?
  private let tokensPerMinute: Int?
  private let admission: SummaryRequestAdmission
  private let lock = NSLock()
  private var identity: Data?
  private var closed = false
  private var requests = 0

  init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral,
    summaryConcurrency: Int? = nil, admission: SummaryRequestAdmission = .shared,
    priority: SummaryRequestAdmission.Priority = .userInitiated,
    requestsPerMinute: Int? = nil, tokensPerMinute: Int? = nil) {
    self.endpoint = endpoint
    self.summaryConcurrency = min(4, max(1, summaryConcurrency ?? 2))
    self.priority = priority
    self.requestsPerMinute = requestsPerMinute
    self.tokensPerMinute = tokensPerMinute
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

  enum RefusedRedirectError: Error, Equatable {
    /// A provider answered with a redirect. Following it could carry
    /// credentials or source text to an origin the person never selected.
    case refusedRedirect
  }

  /// One session for requests that carry a person's credentials. It keeps no
  /// cookies, credential storage or cache, and its delegate never follows a
  /// redirect.
  static func hardenedSession(timeoutInterval: TimeInterval = 30) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeoutInterval
    configuration.timeoutIntervalForResource = timeoutInterval
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
  }

  /// The delegate above refuses redirects; this turns the resulting 3xx into an
  /// explicit error before a body reaches a decoder or a status check.
  static func rejectRefusedRedirect(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (300...399).contains(http.statusCode) else { return }
    throw RefusedRedirectError.refusedRedirect
  }

  func admit(_ request: URLRequest) async throws -> SummaryRequestAdmission.Permit? {
    _ = try bind(request, countRequest: false)
    let fields = [endpoint.absoluteString, request.value(forHTTPHeaderField: "Authorization") ?? "",
      request.value(forHTTPHeaderField: "x-api-key") ?? ""]
    let key = SHA256.hash(data: try JSONEncoder().encode(fields)).map { String(format: "%02x", $0) }.joined()
    var tokenReservation: Int?
    if let data = request.httpBody, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let output = (body["max_completion_tokens"] ?? body["max_tokens"]) as? Int,
       output > 0, output <= 16_000_000 {
      // This is a conservative admission reservation, never billable usage.
      tokenReservation = data.count + output + 2_048
    }
    let currentLimit = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2 ? 1 : summaryConcurrency
    return try await admission.acquire(scope: key, maximumConcurrent: currentLimit, priority: priority,
      requestsPerMinute: requestsPerMinute, tokensPerMinute: tokensPerMinute, tokenReservation: tokenReservation)
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

  /// Non-streaming AI paths share the same credential/endpoint admission.
  func data(for request: URLRequest, maximumBytes: Int = 2 * 1_024 * 1_024, authorize: (@MainActor () -> Bool)? = nil) async throws -> (Data, URLResponse) {
    guard (1...16 * 1_024 * 1_024).contains(maximumBytes) else { throw AIAnswerFailure.executionLimit }
    let permit = try await admit(request)
    do {
      try Task.checkCancellation()
      if let authorize, !(await authorize()) { throw AIAnswerFailure.contextChanged }
      let (bytes, response) = try await self.bytes(for: request)
      await observe(response, permit: permit)
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < maximumBytes else { throw AIAnswerFailure.executionLimit }
        data.append(byte)
      }
      await release(permit)
      return (data, response)
    } catch {
      await release(permit)
      throw error
    }
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
