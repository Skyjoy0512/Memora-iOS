import Foundation
#if !MCP_HTTP_CHECKS
import MCP
import Logging
#endif

actor MCPBoundedHTTPTransport: Transport {
  nonisolated let logger = Logger(label: "memora.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
  private var endpoint: URL
  private var token: String?
  private var presetHeaders: [String: String]
  private let responseState = MCPHTTPResponseState()
  private var version = MCP.Version.latest
  private var http: MCPPinnedHTTP
  private var requests: [UUID: Task<WebSourceHTTPDecoder.Response, Error>] = [:]
  private var stream: AsyncThrowingStream<Data, Error>
  private var continuation: AsyncThrowingStream<Data, Error>.Continuation
  init(endpoint: URL, token: String?, presetHeaders: [String: String] = [:], http: MCPPinnedHTTP = .init()) {
    self.endpoint = endpoint; self.token = token; self.http = http
    self.presetHeaders = presetHeaders
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    stream = pair.stream; continuation = pair.continuation
  }
  func connect() async throws { try responseState.checkOpen() }
  func receive() -> AsyncThrowingStream<Data, Error> { stream }
  func setVersion(_ value: String) { version = value }
  func disconnect() async {
    responseState.disconnect(); token = nil
    for request in requests.values { request.cancel() }
    requests.removeAll(); continuation.finish()
  }
  func send(_ data: Data) async throws {
    try Task.checkCancellation()
    guard data.count <= 64 * 1024 else { throw MCPClientError.malformed }
    let id = UUID(), responseState = responseState
    let sessionID = try responseState.begin(id)
    defer { responseState.end(id); requests[id] = nil }
    var headers = ["Content-Type": "application/json", "Accept": "application/json, text/event-stream", "MCP-Protocol-Version": version]
    headers.merge(presetHeaders) { existing, _ in existing }
    if let sessionID { headers["Mcp-Session-Id"] = sessionID }
    if let token, !token.isEmpty { headers["Authorization"] = "Bearer " + token }
    let continuation = continuation
    let reader = MCPHTTPResponseReader(request: data) { continuation.yield($0) }
    let endpoint = endpoint, http = http
    let task = Task {
      try await http.post(endpoint: endpoint, body: data, headers: headers,
        onResponse: { try responseState.read($0, complete: $1, reader: reader, id: id) })
    }
    requests[id] = task
    _ = try await withTaskCancellationHandler { try await task.value } onCancel: { responseState.end(id); task.cancel() }
    try Task.checkCancellation()
    try responseState.checkOpen()
  }
}
