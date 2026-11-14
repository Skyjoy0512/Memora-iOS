import Foundation

@main
struct MCPPinnedHTTPChecks {
  static let endpoint = URL(string: "https://mcp.example.com/rpc")!
  static let request = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
  static let notification = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
  static let reply = #"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#

  static func main() async throws {
    try requests()
    try decoding()
    try await pinning()
    try await transportLifecycle()
    try await oauthLifecycle()
    print("MCPPinnedHTTPChecks: passed (numeric DNS binding, strict POST/framing, fragmented JSON/SSE, matching reply, no replay, disconnect/caller cancellation, OAuth stale refresh/CAS; fixture transport, no network)")
  }

  static func reject(_ name: String, _ operation: () throws -> Void) {
    do { try operation(); preconditionFailure("Accepted: " + name) } catch {}
  }

  static func requests() throws {
    let request = try WebSourceRequest(url: endpoint, addresses: ["93.184.215.14"], body: request,
      headers: ["Authorization": "Bearer fixture-only", "Content-Type": "application/json", "MCP-Protocol-Version": "2025-11-25"])
    let wire = String(decoding: request.bytes, as: UTF8.self)
    precondition(request.address == "93.184.215.14" && request.host == "mcp.example.com")
    precondition(wire.hasPrefix("POST /rpc HTTP/1.1\r\nHost: mcp.example.com\r\n"))
    precondition(wire.contains("Content-Length: \(Self.request.count)\r\n") && request.bytes.suffix(Self.request.count) == Self.request)
    precondition(!wire.contains("Cookie:") && wire.contains("Accept-Encoding: identity"))
    for headers in [["Host": "private"], ["Content-Length": "0"], ["Accept": "x\r\nHost: private"],
      ["Authorization": "bad\ttoken"], ["accept": "application/json", "Accept": "text/plain"], ["Authorization": "秘密"],
      ["X-MCP-Toolsets": "issues,pull_requests"]] {
      reject("unsafe header") { _ = try WebSourceRequest(url: endpoint, addresses: ["93.184.215.14"], body: Self.request, headers: headers) }
    }
    for addresses in [[], ["127.0.0.1"], ["93.184.215.14", "10.0.0.1"], ["::ffff:127.0.0.1"], ["mcp.example.com"]] {
      reject("unsafe DNS") { _ = try WebSourceRequest(url: endpoint, addresses: addresses, body: Self.request) }
    }
    reject("request cap") { _ = try WebSourceRequest(url: endpoint, addresses: ["93.184.215.14"], body: Data(repeating: 65, count: 65 * 1024)) }
  }

  static func decoder(limit: Int = 2 * 1024 * 1024) -> WebSourceHTTPDecoder {
    .init(maximumBodyBytes: limit, contentTypes: ["application/json", "text/event-stream"], successfulStatuses: 200..<300,
      emptyStatuses: [202, 204], additionalHeaders: ["mcp-session-id"])
  }

  static func response(_ body: String, type: String = "application/json", extra: String = "") -> Data {
    Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\n\(extra)\r\n\(body)".utf8)
  }

  static func consume(_ chunks: [Data], decoder initial: WebSourceHTTPDecoder = decoder(),
                      handler: MCPPinnedHTTP.ResponseHandler? = nil, ended: Bool = true) throws -> WebSourceHTTPDecoder.Response? {
    var decoder = initial
    for (offset, chunk) in chunks.enumerated() {
      let result = try decoder.append(chunk, ended: ended && offset == chunks.count - 1)
      if let snapshot = result ?? decoder.partialResponse, let handler,
         try handler(snapshot, result != nil) { return snapshot }
      if let result { return result }
    }
    return nil
  }

  static func decoding() throws {
    let raw = response(reply, extra: "Mcp-Session-Id: fixture-session\r\n")
    for cut in 1..<raw.count {
      let messages = Messages()
      let reader = MCPHTTPResponseReader(request: request) { messages.append($0) }
      let value = try consume([Data(raw.prefix(cut)), Data(raw.dropFirst(cut))], handler: { try reader.read($0, complete: $1) })
      precondition(value?.body == Data(reply.utf8) && messages.values == [Data(reply.utf8)])
      precondition(value?.headers["mcp-session-id"] == "fixture-session")
    }
    let notice = #"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}"#
    let events = ": ping\r\n\r\ndata: \(notice)\r\n\r\ndata: \(reply)\r\n\r\n"
    let payload = Data(events.utf8)
    let chunk = String(payload.count, radix: 16) + "\r\n" + events + "\r\n"
    // No terminating HTTP chunk or EOF: complete JSON-RPC SSE reply still closes.
    let open = Data(("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n" + chunk).utf8)
    let delivered = Messages()
    let reader = MCPHTTPResponseReader(request: request) { delivered.append($0) }
    let result = try consume(open.map { Data([$0]) }, handler: { try reader.read($0, complete: $1) }, ended: false)
    precondition(result != nil && delivered.values == [Data(notice.utf8), Data(reply.utf8)])
    _ = try reader.read(result!, complete: false)
    precondition(delivered.values.count == 2, "Cumulative snapshots duplicated a message")
    let unfinishedChunk = Data(("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n1000\r\n" + events).utf8)
    let early = Messages()
    let earlyReader = MCPHTTPResponseReader(request: request) { early.append($0) }
    let earlyResult = try consume(unfinishedChunk.map { Data([$0]) }, handler: { try earlyReader.read($0, complete: $1) }, ended: false)
    precondition(earlyResult != nil && early.values.count == 2, "Complete SSE reply waited for the HTTP chunk to end")
    for body in ["data: \(reply)", "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}\n\n", "data: {broken}\n\n", "data: \(notice)\n\n"] {
      reject("missing, truncated or wrong SSE reply") {
        let reader = MCPHTTPResponseReader(request: request) { _ in precondition(!body.contains("broken")) }
        _ = try consume([response(body, type: "text/event-stream")], handler: { try reader.read($0, complete: $1) })
      }
    }
    let invalidUTF8 = Data([0x64, 0x61, 0x74, 0x61, 0x3a, 0xff, 10, 10])
    reject("invalid SSE UTF8") {
      let reader = MCPHTTPResponseReader(request: request) { _ in preconditionFailure("Invalid event delivered") }
      _ = try reader.read(.init(status: 200, headers: ["content-type": "text/event-stream"], body: invalidUTF8), complete: true)
    }
    for body in [#"{"jsonrpc":"2.0","id":2,"result":{}}"#, #"{"jsonrpc":"2.0","id":1}"#,
      #"{"jsonrpc":"2.0","id":1,"result":{},"error":{}}"#, #"{"jsonrpc":"2.0","id":true,"result":{}}"#,
      #"{"jsonrpc":"2.0","id":1,"error":{"code":true,"message":"bad"}}"#, "[]", "{broken}"] {
      reject("invalid JSON reply") {
        let reader = MCPHTTPResponseReader(request: request) { _ in preconditionFailure("Invalid response delivered") }
        _ = try consume([response(body)], handler: { try reader.read($0, complete: $1) })
      }
    }
    for header in ["Content-Length: 3\r\nTransfer-Encoding: chunked", "Content-Length: 1\r\nContent-Length: 1",
      "Mcp-Session-Id: a\r\nMcp-Session-Id: b", "Content-Length: 2097153", "Content-Encoding: gzip", "Transfer-Encoding: gzip"] {
      reject("invalid HTTP framing") {
        _ = try consume([Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\(header)\r\n\r\nx".utf8)])
      }
    }
    reject("partial HTTP JSON") { _ = try consume([Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 80\r\n\r\n{}".utf8)]) }
    for id in ["", String(repeating: "s", count: 513), "has space"] {
      reject("invalid session") {
        let reader = MCPHTTPResponseReader(request: request) { _ in preconditionFailure("Invalid session delivered") }
        _ = try consume([response(reply, extra: "Mcp-Session-Id: \(id)\r\n")], handler: { try reader.read($0, complete: $1) })
      }
    }
    for status in [202, 204] {
      let accepted = Data("HTTP/1.1 \(status) Accepted\r\nContent-Length: 0\r\n\r\n".utf8)
      let reader = MCPHTTPResponseReader(request: notification) { _ in preconditionFailure("Empty ack delivered") }
      let acknowledgement = try consume([accepted], handler: { try reader.read($0, complete: $1) })
      precondition(acknowledgement != nil)
      let serverReply = Data(#"{"jsonrpc":"2.0","id":"server-request","result":{}}"#.utf8)
      let responseReader = MCPHTTPResponseReader(request: serverReply) { _ in preconditionFailure("Ack became reply") }
      _ = try consume([accepted], handler: { try responseReader.read($0, complete: $1) })
      reject("empty ack for request") {
        let reader = MCPHTTPResponseReader(request: request) { _ in preconditionFailure() }
        _ = try consume([accepted], handler: { try reader.read($0, complete: $1) })
      }
    }
    _ = try consume([response(String(repeating: "x", count: 128 * 1024))], decoder: decoder(limit: 128 * 1024))
    reject("OAuth response cap") { _ = try consume([response(String(repeating: "x", count: 128 * 1024 + 1))], decoder: decoder(limit: 128 * 1024)) }
  }

  static func pinning() async throws {
    let calls = Calls()
    let http = MCPPinnedHTTP(resolve: { host in
      await calls.record("dns:" + host)
      return ["93.184.215.14"]
    }, transfer: { request, decoder, handler in
      await calls.record("ip:" + request.address)
      // A later DNS answer could now be private; transfer gets no resolver.
      precondition(request.host == "mcp.example.com" && request.address == "93.184.215.14")
      return try consume([response(reply)], decoder: decoder, handler: handler)!
    })
    _ = try await http.post(endpoint: endpoint, body: request, headers: [:])
    let history = await calls.values
    precondition(history == ["dns:mcp.example.com", "ip:93.184.215.14"])
    let unsafe = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14", "127.0.0.1"] }, transfer: { _, _, _ in preconditionFailure("Unsafe DNS reached transport") })
    do { _ = try await unsafe.post(endpoint: endpoint, body: request, headers: [:]); preconditionFailure() } catch MCPClientError.invalidURL {}
    for status in [301, 302, 307, 308, 401, 429, 500] {
      let calls = Calls()
      let denied = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { _, decoder, handler in
        await calls.record("send")
        return try consume([Data("HTTP/1.1 \(status) Error\r\nLocation: https://private.example.com/\r\n\r\n".utf8)], decoder: decoder, handler: handler)!
      })
      do { _ = try await denied.post(endpoint: endpoint, body: request, headers: [:]); preconditionFailure() }
      catch let failure as ExternalToolFailure { precondition(failure == ExternalToolFailure.http(status)) }
      let sent = await calls.values
      precondition(sent.count == 1, "Redirect followed or failed request replayed")
    }
    let timeout = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { _, _, _ in throw WebSourceFailure.timeout })
    do { _ = try await timeout.post(endpoint: endpoint, body: request, headers: [:]); preconditionFailure() } catch MCPClientError.timeout {}
  }

  static func transportLifecycle() async throws {
    let endpoint = URL(string: "https://api.githubcopilot.com/mcp/readonly")!
    reject("provider write override") {
      _ = try WebSourceRequest(url: endpoint, addresses: ["93.184.215.14"], body: request, headers: ["X-MCP-Readonly": "false"])
    }
    let requests = Messages()
    let http = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { request, decoder, handler in
      requests.append(request.bytes)
      let raw = requests.values.count == 1 ? response(reply, extra: "Mcp-Session-Id: fixture-session\r\n") : Data("HTTP/1.1 202 Accepted\r\n\r\n".utf8)
      return try consume([raw], decoder: decoder, handler: handler)!
    })
    let transport = MCPBoundedHTTPTransport(endpoint: endpoint, token: "fixture-only",
      presetHeaders: MCPServerConfig.Preset.github.server().presetHeaders, http: http)
    try await transport.connect()
    var iterator = await transport.receive().makeAsyncIterator()
    try await transport.send(request)
    let received = try await iterator.next()
    precondition(received == Data(reply.utf8))
    try await transport.send(notification)
    precondition(String(decoding: requests.values[1], as: UTF8.self).contains("mcp-session-id: fixture-session\r\n"))
    let wire = String(decoding: requests.values[0], as: UTF8.self)
    precondition(wire.contains("x-mcp-toolsets: issues,pull_requests\r\n") && wire.contains("x-mcp-readonly: true\r\n"))
    precondition(wire.contains("authorization: Bearer fixture-only\r\n"))
    try await transport.send(Data(#"{"jsonrpc":"2.0","id":"server-request","result":{}}"#.utf8))
    await transport.disconnect()
    let terminal = try await iterator.next()
    precondition(terminal == nil)
    do { try await transport.send(request); preconditionFailure("Send after disconnect") } catch is CancellationError {}
    precondition(requests.values.count == 3)
    // Deliver initialize's reply while its send is deliberately still suspended.
    // The SDK may already send notifications/initialized on this same transport.
    let replyGate = Gate(), raceRequests = Messages()
    let sessionRace = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { request, decoder, handler in
      raceRequests.append(request.bytes)
      if raceRequests.values.count == 1 {
        let response = try consume([response(reply, extra: "Mcp-Session-Id: early-session\r\n")], decoder: decoder, handler: handler)!
        await replyGate.releaseWait()
        return response
      }
      precondition(String(decoding: request.bytes, as: UTF8.self).contains("mcp-session-id: early-session\r\n"))
      return try consume([Data("HTTP/1.1 202 Accepted\r\n\r\n".utf8)], decoder: decoder, handler: handler)!
    })
    let racing = MCPBoundedHTTPTransport(endpoint: endpoint, token: nil, http: sessionRace)
    var raceIterator = await racing.receive().makeAsyncIterator()
    let first = Task { try await racing.send(request) }
    let firstReply = try await raceIterator.next()
    precondition(firstReply == Data(reply.utf8))
    try await racing.send(notification)
    await replyGate.release()
    try await first.value
    await racing.disconnect()
    let state = MCPHTTPResponseState(), stateID = UUID()
    _ = try state.begin(stateID)
    let stateReader = MCPHTTPResponseReader(request: request) { _ in }
    _ = try state.read(.init(status: 200, headers: ["content-type": "application/json", "mcp-session-id": "original"], body: Data()), complete: false, reader: stateReader, id: stateID)
    reject("session replacement by another response") {
      _ = try state.read(.init(status: 200, headers: ["content-type": "application/json", "mcp-session-id": "replacement"], body: Data()), complete: false, reader: stateReader, id: stateID)
    }
    let nextSession = try state.begin(UUID())
    precondition(nextSession == "original")
    for callerCancellation in [false, true] {
      let gate = Gate()
      let stalled = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { _, _, _ in
        await gate.arrive()
        try await Task.sleep(for: .seconds(30))
        preconditionFailure("Cancelled transfer resumed")
      })
      let transport = MCPBoundedHTTPTransport(endpoint: endpoint, token: nil, http: stalled)
      let sending = Task { try await transport.send(request) }
      await gate.wait()
      if callerCancellation { sending.cancel() } else { await transport.disconnect() }
      do { try await sending.value; preconditionFailure("Cancellation ignored") } catch is CancellationError {}
      await transport.disconnect()
    }
    let lateGate = Gate()
    let lateHTTP = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { _, decoder, handler in
      await lateGate.arrive(); await lateGate.releaseWait()
      return try consume([response(reply, extra: "Mcp-Session-Id: too-late\r\n")], decoder: decoder, handler: handler)!
    })
    let late = MCPBoundedHTTPTransport(endpoint: endpoint, token: nil, http: lateHTTP)
    var lateIterator = await late.receive().makeAsyncIterator()
    let pending = Task { try await late.send(request) }
    await lateGate.wait()
    await late.disconnect()
    await lateGate.release()
    do { try await pending.value; preconditionFailure("Late callback revived disconnected transport") } catch is CancellationError {}
    let lateMessage = try await lateIterator.next()
    precondition(lateMessage == nil)
  }

  static func oauthLifecycle() async throws {
    let settings = MCPOAuthSettings(clientID: "fixture-client", authorizationURL: "https://auth.example.com/authorize", tokenURL: "https://auth.example.com/token", scopes: "read:notes")
    var server = MCPServerConfig(id: UUID(), name: "Fixture", url: endpoint.absoluteString)
    server.oauth = settings
    let tokenBody = #"{"access_token":"fixture-renewed","token_type":"bearer","expires_in":3600}"#
    let normal = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { request, decoder, handler in
      precondition(request.host == "auth.example.com" && request.address == "93.184.215.14")
      let wire = String(decoding: request.bytes, as: UTF8.self)
      precondition(wire.contains("content-type: application/x-www-form-urlencoded\r\n") && wire.contains("code_verifier=fixture-verifier"))
      return try consume([response(tokenBody)], decoder: decoder, handler: handler)!
    })
    let exchanged = try await MCPOAuthClient(http: normal).exchange(code: "fixture-code", verifier: "fixture-verifier", server: server)
    precondition(exchanged.accessToken == "fixture-renewed")
    for cancelled in [false, true] {
      let gate = Gate()
      let slow = MCPPinnedHTTP(resolve: { _ in ["93.184.215.14"] }, transfer: { _, decoder, handler in
        await gate.arrive(); await gate.releaseWait()
        return try consume([response(tokenBody)], decoder: decoder, handler: handler)!
      })
      let client = MCPOAuthClient(http: slow)
      let credential = MCPOAuthCredential(identity: try MCPOAuthPolicy.identity(endpoint: server.url, settings: settings), accessToken: "fixture-expired",
        refreshToken: "fixture-refresh", expiresAt: .distantPast, scopes: ["read:notes"])
      let original = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
      KeychainStore.seed(original, forKey: server.oauthAccount)
      let immutableServer = server
      let refresh = Task { try await client.accessToken(for: immutableServer) }
      await gate.wait()
      if cancelled { await client.cancel(server.id) }
      else { KeychainStore.seed("newer-authorization", forKey: server.oauthAccount) }
      await gate.release()
      do { _ = try await refresh.value; preconditionFailure("Stale or cancelled refresh persisted") }
      catch is CancellationError { precondition(cancelled) }
      catch MCPOAuthError.reauthentication { precondition(!cancelled) }
      precondition(KeychainStore.string(forKey: server.oauthAccount) == (cancelled ? original : "newer-authorization"))
      KeychainStore.seed(nil, forKey: server.oauthAccount)
    }
  }

  final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data] = []
    var values: [Data] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ value: Data) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
  }
  actor Calls {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
  }
  actor Gate {
    private var arrived = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var releases: [CheckedContinuation<Void, Never>] = []
    func arrive() { arrived = true; arrivals.forEach { $0.resume() }; arrivals.removeAll() }
    func wait() async { if !arrived { await withCheckedContinuation { arrivals.append($0) } } }
    func release() { released = true; releases.forEach { $0.resume() }; releases.removeAll() }
    func releaseWait() async { if !released { await withCheckedContinuation { releases.append($0) } } }
  }
}
