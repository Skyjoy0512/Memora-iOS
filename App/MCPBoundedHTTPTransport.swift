import Foundation
import MCP
import Logging

actor MCPBoundedHTTPTransport: Transport {
  nonisolated let logger = Logger(label: "memora.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
  private var endpoint: URL
  private var token: String?
  private var sessionID: String?
  private var version = MCP.Version.latest
  private var session: URLSession
  private var stream: AsyncThrowingStream<Data, Error>
  private var continuation: AsyncThrowingStream<Data, Error>.Continuation
  init(endpoint: URL, token: String?) {
    self.endpoint = endpoint; self.token = token
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    stream = pair.stream; continuation = pair.continuation
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    session = URLSession(configuration: configuration, delegate: ProjectMetadataRedirectPolicy(), delegateQueue: nil)
  }
  func connect() async throws {}
  func receive() -> AsyncThrowingStream<Data, Error> { stream }
  func setVersion(_ value: String) { version = value }
  func disconnect() async { session.invalidateAndCancel(); continuation.finish() }
  func send(_ data: Data) async throws {
    guard data.count <= 64 * 1024 else { throw MCPClientError.malformed }
    guard let host = endpoint.host else { throw MCPClientError.invalidURL }
    try await MCPPublicAddressPolicy.validateHost(host)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"; request.httpBody = data
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
    if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
    if let token, !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.url == endpoint else { throw MCPClientError.malformed }
    guard (200..<300).contains(http.statusCode) else { throw ExternalToolFailure.http(http.statusCode) }
    if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
      guard id.utf8.count <= 512, !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw MCPClientError.malformed }
      sessionID = id
    }
    guard http.expectedContentLength <= 2 * 1024 * 1024 else { throw MCPClientError.malformed }
    let outgoingID = MCPEventStream.requestID(data)
    var receivedBytes = 0
    var body = Data()
    let sse = http.mimeType == "text/event-stream"
    guard sse || http.mimeType == "application/json" || http.statusCode == 202 || http.statusCode == 204 else { throw MCPClientError.malformed }
    for try await byte in bytes {
      try Task.checkCancellation()
      receivedBytes += 1
      guard receivedBytes <= 2 * 1024 * 1024 else { throw MCPClientError.malformed }
      body.append(byte)
      if sse, MCPEventStream.isBoundary(body) {
        if let event = MCPEventStream.payload(body) {
          continuation.yield(event)
          if let outgoingID, MCPEventStream.requestID(event) == outgoingID { return }
        }
        body.removeAll(keepingCapacity: true)
      }
    }
    if !body.isEmpty && !sse { continuation.yield(body) }
  }
}
