import Foundation
import Network
import Security

/// State and continuation are owned by one serial queue, including cancellation
/// before start. Network.framework connects to the validated IP, not fresh DNS.
final class PinnedHTTPSConnection: @unchecked Sendable {
  private let queue = DispatchQueue(label: "app.memora.web-source", qos: .utility)
  private let connection: NWConnection
  private var request: WebSourceRequest
  private var decoder = WebSourceHTTPDecoder()
  private var continuation: CheckedContinuation<WebSourceHTTPDecoder.Response, Error>?
  private var completed: Result<WebSourceHTTPDecoder.Response, Error>?
  private var deadline: DispatchWorkItem?

  init(request: WebSourceRequest) throws {
    guard MCPPublicAddressPolicy.isPublic(request.address),
          (try? WebSourceRequest.checkedURL(request.url)) != nil else { throw WebSourceFailure.unsafeAddress }
    self.request = request
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, request.host)
    sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
    sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
    sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
      let reference = sec_trust_copy_ref(trust).takeRetainedValue()
      complete(Self.trusts(reference, hostname: request.host))
    }, DispatchQueue.global(qos: .utility))
    let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    connection = NWConnection(host: NWEndpoint.Host(request.address), port: 443, using: parameters)
  }

  static func trusts(_ reference: SecTrust, hostname: String) -> Bool {
    let policy = SecPolicyCreateSSL(true, hostname as CFString)
    // Certificate AIA/OCSP endpoints must not create unvalidated fetches.
    guard SecTrustSetPolicies(reference, policy) == errSecSuccess,
          SecTrustSetNetworkFetchAllowed(reference, false) == errSecSuccess else { return false }
    return SecTrustEvaluateWithError(reference, nil)
  }

  static func fetch(_ request: WebSourceRequest) async throws -> WebSourceHTTPDecoder.Response {
    let exchange = try PinnedHTTPSConnection(request: request)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { exchange.start($0) }
    } onCancel: { exchange.cancel() }
  }

  private func start(_ value: CheckedContinuation<WebSourceHTTPDecoder.Response, Error>) {
    queue.async { [self] in
      if let completed = self.completed { value.resume(with: completed); return }
      self.continuation = value
      let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(WebSourceFailure.timeout)) }
      self.deadline = deadline
      self.queue.asyncAfter(deadline: .now() + 15, execute: deadline)
      self.connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          self.connection.send(content: self.request.bytes, completion: .contentProcessed { error in
            if error != nil { self.finish(.failure(WebSourceFailure.network)) }
            else { self.receive() }
          })
        case .failed(let error):
          if case .tls = error { self.finish(.failure(WebSourceFailure.certificate)) }
          else { self.finish(.failure(WebSourceFailure.network)) }
        case .cancelled: self.finish(.failure(CancellationError()))
        default: break
        }
      }
      self.connection.start(queue: self.queue)
    }
  }

  private func receive() {
    guard completed == nil else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { data, _, ended, error in
      guard self.completed == nil else { return }
      do {
        if let response = try self.decoder.append(data ?? Data(), ended: ended) { self.finish(.success(response)) }
        else if error != nil { self.finish(.failure(WebSourceFailure.network)) }
        else { self.receive() }
      } catch { self.finish(.failure(error)) }
    }
  }

  private func cancel() { queue.async { self.finish(.failure(CancellationError())) } }

  private func finish(_ result: Result<WebSourceHTTPDecoder.Response, Error>) {
    guard completed == nil else { return }
    completed = result
    deadline?.cancel(); deadline = nil
    connection.stateUpdateHandler = nil
    connection.cancel()
    continuation?.resume(with: result); continuation = nil
  }
}
