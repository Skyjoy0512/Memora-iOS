import Foundation
import CoreFoundation

/// The lock keeps incremental state safe even in injected transports. HTTP body
/// snapshots are cumulative; only newly decoded bytes may produce messages.
final class MCPHTTPResponseReader: @unchecked Sendable {
  private let lock = NSLock()
  private var consumed = 0
  private var event = Data()
  private var matched = false
  private var expectedID: Data?
  private var yield: @Sendable (Data) -> Void

  init(request: Data, yield: @escaping @Sendable (Data) -> Void) {
    let object = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any]
    // Responses to server-initiated requests also carry IDs, but must receive
    // an empty HTTP acknowledgement, not another JSON-RPC response.
    expectedID = object?["method"] is String ? MCPEventStream.requestID(request) : nil
    self.yield = yield
  }

  func read(_ response: WebSourceHTTPDecoder.Response, complete: Bool) throws -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !matched else { return true }
    guard (200..<300).contains(response.status) else { throw ExternalToolFailure.http(response.status) }
    _ = try Self.sessionID(response)
    if response.status == 202 || response.status == 204 {
      guard expectedID == nil, response.body.isEmpty else { throw MCPClientError.malformed }
      return complete
    }
    let type = response.headers["content-type"]?.lowercased().components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
    guard type == "application/json" || type == "text/event-stream",
          response.body.count >= consumed, response.body.count <= WebSourceHTTPDecoder.maximumBodyBytes else { throw MCPClientError.malformed }
    if type == "application/json" {
      guard complete else { return false }
      let isResponse = try validate(response.body)
      guard isResponse, let expectedID, MCPEventStream.requestID(response.body) == expectedID else { throw MCPClientError.malformed }
      matched = true; yield(response.body)
      return true
    }
    for byte in response.body.dropFirst(consumed) {
      event.append(byte)
      if MCPEventStream.isBoundary(event) {
        guard String(data: event, encoding: .utf8) != nil else { throw MCPClientError.malformed }
        if let payload = MCPEventStream.payload(event) {
          let isResponse = try validate(payload)
          if isResponse {
            guard let expectedID, MCPEventStream.requestID(payload) == expectedID else { throw MCPClientError.malformed }
            matched = true
          }
          yield(payload)
        }
        event.removeAll(keepingCapacity: true)
        if matched { return true }
      }
    }
    consumed = response.body.count
    if complete {
      // An HTTP EOF or a cut-off SSE event is not a JSON-RPC response.
      guard event.isEmpty, expectedID == nil else { throw MCPClientError.malformed }
    }
    return complete
  }

  static func sessionID(_ response: WebSourceHTTPDecoder.Response) throws -> String? {
    guard let id = response.headers["mcp-session-id"] else { return nil }
    guard !id.isEmpty, id.utf8.count <= 512, id.utf8.allSatisfy({ (33...126).contains($0) }) else { throw MCPClientError.malformed }
    return id
  }

  private func validate(_ data: Data) throws -> Bool {
    guard String(data: data, encoding: .utf8) != nil,
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          object["jsonrpc"] as? String == "2.0" else { throw MCPClientError.malformed }
    if let id = object["id"] {
      guard id is String || Self.integer(id) else { throw MCPClientError.malformed }
    }
    if let method = object["method"] as? String, !method.isEmpty {
      guard object["result"] == nil, object["error"] == nil else { throw MCPClientError.malformed }
      return false
    }
    guard MCPEventStream.requestID(data) != nil, (object["result"] != nil) != (object["error"] != nil) else { throw MCPClientError.malformed }
    if let error = object["error"] {
      guard let fields = error as? [String: Any], let code = fields["code"], Self.integer(code),
            fields["message"] is String else { throw MCPClientError.malformed }
    }
    return true
  }

  private static func integer(_ value: Any) -> Bool {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    return Int64(exactly: number.doubleValue) != nil
  }
}
