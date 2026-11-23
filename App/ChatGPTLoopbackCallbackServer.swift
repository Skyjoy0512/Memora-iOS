import Foundation
import Network

/// Why a ChatGPT sign-in callback could not be received.
enum ChatGPTLoopbackError: LocalizedError, Equatable {
  /// The sign-in was cancelled before a usable callback arrived.
  case cancelled
  /// The loopback listener could not start or stopped unexpectedly.
  case unavailable
  /// The callback did not carry exactly one usable authorization code.
  case invalidCallback

  var errorDescription: String? {
    switch self {
    case .cancelled:
      return "ChatGPTのサインインは中止されました。"
    case .unavailable:
      return "サインインの受付口を開けませんでした。もう一度お試しください。"
    case .invalidCallback:
      return "ChatGPTからの応答を確認できませんでした。もう一度サインインしてください。"
    }
  }
}

/// The values a successful loopback callback carries.
struct ChatGPTLoopbackCallback: Equatable, Sendable {
  /// The single authorization code from the callback.
  var code: String
  /// The client ID from the callback, when it carried one.
  var clientID: String?
}

/// A one-shot loopback listener for the ChatGPT sign-in callback.
///
/// The listener binds to IPv4 loopback on an ephemeral port, waits for one
/// request that matches the callback path, host and state, and then stops.
final class ChatGPTLoopbackCallbackServer: @unchecked Sendable {
  /// The path the loopback callback answers on.
  static let callbackPath = "/auth/callback"

  private static let maximumRequestBytes = 8 * 1024
  private static let maximumChunkBytes = 4 * 1024
  private static let successPage = """
    <!doctype html>
    <html lang="ja">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>サインイン完了</title>
    </head>
    <body>
    <main>
    <h1>サインインが完了しました</h1>
    <p>このページを閉じて、Memoraに戻ってください。</p>
    </main>
    </body>
    </html>
    """
  private static let failurePage = """
    <!doctype html>
    <html lang="ja">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>サインインを完了できませんでした</title>
    </head>
    <body>
    <main>
    <h1>サインインを完了できませんでした</h1>
    <p>Memoraに戻って、もう一度お試しください。</p>
    </main>
    </body>
    </html>
    """

  private let lock = NSLock()
  private let queue = DispatchQueue(label: "app.memora.chatgpt.loopback")
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var continuation: CheckedContinuation<(callback: ChatGPTLoopbackCallback, redirectURI: URL), Error>?
  private var portContinuation: CheckedContinuation<UInt16, Error>?
  private var expectedState: String?
  private var port: UInt16?
  private var redirectURI: URL?
  private var started = false
  private var finished = false
  private var terminalError: ChatGPTLoopbackError?

  /// Waits for the callback that matches `state`.
  ///
  /// `start()` must have been called first, so the redirect URI carried by
  /// the authorization request is the one this listener answers on, and
  /// `expect(state:)` must have set the state the request carries.
  ///
  /// Returns the callback and the redirect URI that was used, so the
  /// caller can send the same redirect URI with the code exchange.
  ///
  /// Throws `ChatGPTLoopbackError.unavailable` when the listener is not
  /// running, and `ChatGPTLoopbackError.cancelled` when `cancel()` is
  /// called before the callback arrives.
  func waitForCallback(state: String) async throws -> (callback: ChatGPTLoopbackCallback, redirectURI: URL) {
    guard !state.isEmpty else { throw ChatGPTLoopbackError.invalidCallback }
    return try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      guard !finished, self.continuation == nil, listener != nil else {
        let error = terminalError ?? ChatGPTLoopbackError.unavailable
        lock.unlock()
        continuation.resume(throwing: error)
        return
      }
      self.continuation = continuation
      lock.unlock()
    }
  }

  /// Binds the listener and returns the redirect URI it answers on.
  ///
  /// The authorization request must carry this exact URI, so the port has to
  /// be known before the browser is opened. The listener waits for the
  /// callback that matches the state afterwards.
  func start() async throws -> URL {
    if Task.isCancelled {
      cancel()
      throw ChatGPTLoopbackError.cancelled
    }

    let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
      lock.lock()
      if finished {
        let error = terminalError ?? ChatGPTLoopbackError.unavailable
        lock.unlock()
        continuation.resume(throwing: error)
        return
      }
      guard !started else {
        lock.unlock()
        continuation.resume(throwing: ChatGPTLoopbackError.unavailable)
        return
      }
      started = true
      portContinuation = continuation
      lock.unlock()

      let listener: NWListener
      do {
        listener = try Self.makeListener()
      } catch {
        finish(.failure(.unavailable))
        return
      }

      lock.lock()
      guard !finished, self.listener == nil else {
        lock.unlock()
        listener.cancel()
        return
      }
      self.listener = listener
      listener.stateUpdateHandler = { [weak self] state in
        self?.listenerStateChanged(state)
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      lock.unlock()
      listener.start(queue: queue)
    }
    guard let url = URL(string: "http://127.0.0.1:\(port)\(Self.callbackPath)") else {
      cancel()
      throw ChatGPTLoopbackError.unavailable
    }
    return url
  }

  /// Stops the listener and completes an outstanding wait as cancelled.
  func cancel() {
    finish(.failure(.cancelled))
  }

  /// Sets the state the callback must carry.
  ///
  /// The state belongs to the authorization request, so it is known only
  /// after the request was built, which happens after the listener bound its
  /// port. A callback with another state is refused and does not end the
  /// wait.
  func expect(state: String) {
    lock.lock()
    expectedState = state
    lock.unlock()
  }

  private static func makeListener() throws -> NWListener {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 0)
    return try NWListener(using: parameters)
  }

  private func listenerStateChanged(_ state: NWListener.State) {
    switch state {
    case .ready:
      lock.lock()
      if finished {
        lock.unlock()
        return
      }
      guard let currentListener = listener,
            let selectedPort = currentListener.port?.rawValue,
            let url = URL(string: "http://127.0.0.1:\(selectedPort)\(Self.callbackPath)") else {
        lock.unlock()
        finish(.failure(.unavailable))
        return
      }
      port = selectedPort
      redirectURI = url
      let pendingPort = portContinuation
      portContinuation = nil
      lock.unlock()
      pendingPort?.resume(returning: selectedPort)
    case .failed(_), .cancelled:
      finish(.failure(.unavailable))
    default:
      break
    }
  }

  private func accept(_ connection: NWConnection) {
    lock.lock()
    guard !finished, listener != nil else {
      lock.unlock()
      connection.cancel()
      return
    }
    connections[ObjectIdentifier(connection)] = connection
    lock.unlock()

    connection.stateUpdateHandler = { [weak self, weak connection] state in
      switch state {
      case .failed(_), .cancelled:
        if let connection = connection {
          self?.removeConnection(connection)
        }
      default:
        break
      }
    }
    connection.start(queue: queue)
    receive(on: connection, buffer: Data())
  }

  private func receive(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumChunkBytes) {
      [weak self] data, _, isComplete, error in
      guard let self = self else {
        connection.cancel()
        return
      }
      var received = buffer
      if let data = data {
        received.append(data)
      }
      if let end = received.range(of: Data("\r\n\r\n".utf8)) {
        guard end.lowerBound <= Self.maximumRequestBytes else {
          self.respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
          return
        }
        let headers = Data(received[..<end.lowerBound])
        self.process(headers: headers, on: connection)
        return
      }
      if received.count > Self.maximumRequestBytes || error != nil || isComplete {
        self.respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
        return
      }
      self.receive(on: connection, buffer: received)
    }
  }

  private func process(headers: Data, on connection: NWConnection) {
    guard let text = String(data: headers, encoding: .utf8) else {
      respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
      return
    }

    let lines = text.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
      respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
      return
    }
    let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count == 3, String(parts[0]) == "GET",
          String(parts[2]).hasPrefix("HTTP/") else {
      respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
      return
    }

    let target = String(parts[1])
    let targetParts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    guard let pathPart = targetParts.first, String(pathPart) == Self.callbackPath else {
      respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
      return
    }
    let query = targetParts.count == 2 ? String(targetParts[1]) : ""

    var hosts: [String] = []
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else {
        respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
        return
      }
      let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
      let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty else {
        respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
        return
      }
      if name == "host" {
        hosts.append(value)
      }
    }

    guard let selectedPort = selectedPortValue(),
          hosts.count == 1,
          hosts[0] == "127.0.0.1:\(selectedPort)" else {
      respond(connection, statusCode: 404, reason: "Not Found", html: Self.failurePage)
      return
    }

    guard let values = queryValues(query) else {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage)
      return
    }
    let states = values["state"] ?? []
    guard states.count == 1,
          let state = states.first,
          !state.isEmpty,
          let expectedState = expectedStateValue(),
          state == expectedState else {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage)
      return
    }

    if values["error"] != nil {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage,
        terminal: .failure(.invalidCallback))
      return
    }

    let codes = values["code"] ?? []
    guard codes.count == 1, let code = codes.first, !code.isEmpty else {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage,
        terminal: .failure(.invalidCallback))
      return
    }

    let clientIDs = values["client_id"] ?? []
    guard clientIDs.count <= 1 else {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage,
        terminal: .failure(.invalidCallback))
      return
    }
    let clientID = clientIDs.first.flatMap { value -> String? in
      value.isEmpty ? nil : value
    }
    guard let redirectURI = redirectURIValue()
      ?? URL(string: "http://127.0.0.1:\(selectedPort)\(Self.callbackPath)") else {
      respond(connection, statusCode: 400, reason: "Bad Request", html: Self.failurePage,
        terminal: .failure(.unavailable))
      return
    }
    let callback = ChatGPTLoopbackCallback(code: code, clientID: clientID)
    respond(connection, statusCode: 200, reason: "OK", html: Self.successPage,
      terminal: .success((callback: callback, redirectURI: redirectURI)))
  }

  private func queryValues(_ query: String) -> [String: [String]]? {
    guard !query.isEmpty else { return [:] }
    var values: [String: [String]] = [:]
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let rawName = parts.first,
            let name = String(rawName).removingPercentEncoding,
            !name.isEmpty else {
        return nil
      }
      let rawValue = parts.count == 2 ? String(parts[1]) : ""
      guard let value = rawValue.removingPercentEncoding else { return nil }
      values[name, default: []].append(value)
    }
    return values
  }

  private func selectedPortValue() -> UInt16? {
    lock.lock()
    defer { lock.unlock() }
    if let port = port {
      return port
    }
    let selectedPort = listener?.port?.rawValue
    if let selectedPort = selectedPort {
      port = selectedPort
    }
    return selectedPort
  }

  private func expectedStateValue() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return expectedState
  }

  private func redirectURIValue() -> URL? {
    lock.lock()
    defer { lock.unlock() }
    return redirectURI
  }

  private func respond(_ connection: NWConnection, statusCode: Int, reason: String, html: String,
    terminal: Result<(callback: ChatGPTLoopbackCallback, redirectURI: URL), ChatGPTLoopbackError>? = nil) {
    if let terminal = terminal {
      guard finish(terminal, keeping: connection) else {
        connection.cancel()
        removeConnection(connection)
        return
      }
    }
    let body = Data(html.utf8)
    let header = "HTTP/1.1 \(statusCode) \(reason)\r\n"
      + "Content-Type: text/html; charset=utf-8\r\n"
      + "Cache-Control: no-store\r\n"
      + "Content-Length: \(body.count)\r\n"
      + "Connection: close\r\n\r\n"
    let response = Data(header.utf8) + body
    connection.send(content: response, completion: .contentProcessed { [weak self] _ in
      connection.cancel()
      self?.removeConnection(connection)
    })
  }

  private func removeConnection(_ connection: NWConnection) {
    lock.lock()
    connections.removeValue(forKey: ObjectIdentifier(connection))
    lock.unlock()
  }

  @discardableResult
  private func finish(
    _ result: Result<(callback: ChatGPTLoopbackCallback, redirectURI: URL), ChatGPTLoopbackError>,
    keeping keptConnection: NWConnection? = nil) -> Bool {
    var stoppedListener: NWListener?
    var cancelledConnections: [NWConnection] = []
    var wait: CheckedContinuation<(callback: ChatGPTLoopbackCallback, redirectURI: URL), Error>?
    var pendingPort: CheckedContinuation<UInt16, Error>?

    lock.lock()
    guard !finished else {
      lock.unlock()
      return false
    }
    finished = true
    if case .failure(let error) = result {
      terminalError = error
    }
    stoppedListener = listener
    listener = nil
    let keptIdentifier: ObjectIdentifier? = keptConnection.map { ObjectIdentifier($0) }
    var removed: [ObjectIdentifier] = []
    for (identifier, connection) in connections {
      if identifier == keptIdentifier {
        continue
      }
      cancelledConnections.append(connection)
      removed.append(identifier)
    }
    for identifier in removed {
      connections.removeValue(forKey: identifier)
    }
    wait = continuation
    continuation = nil
    pendingPort = portContinuation
    portContinuation = nil
    expectedState = nil
    redirectURI = nil
    lock.unlock()

    stoppedListener?.stateUpdateHandler = nil
    stoppedListener?.newConnectionHandler = nil
    stoppedListener?.cancel()
    for connection in cancelledConnections {
      connection.stateUpdateHandler = nil
      connection.cancel()
    }

    if let pendingPort {
      pendingPort.resume(throwing: terminalError ?? ChatGPTLoopbackError.unavailable)
    }
    if let wait = wait {
      switch result {
      case .success(let value):
        wait.resume(returning: value)
      case .failure(let error):
        wait.resume(throwing: error)
      }
    }
    return true
  }
}
