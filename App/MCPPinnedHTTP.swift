import Foundation

/// DNS approval and the numeric socket destination belong to the same exchange.
/// No redirect, proxy, URLSession fallback, or automatic replay is permitted.
struct MCPPinnedHTTP: Sendable {
  typealias ResponseHandler = @Sendable (WebSourceHTTPDecoder.Response, Bool) throws -> Bool
  var resolve: @Sendable (String) async throws -> [String] = { try await MCPPublicAddressPolicy.validatedAddresses(for: $0) }
  var transfer: @Sendable (WebSourceRequest, WebSourceHTTPDecoder, ResponseHandler?) async throws -> WebSourceHTTPDecoder.Response = {
    try await PinnedHTTPSConnection.fetch($0, decoder: $1, timeout: 30, responseHandler: $2)
  }

  func post(endpoint: URL, body: Data, headers: [String: String],
            maximumResponseBytes: Int = WebSourceHTTPDecoder.maximumBodyBytes,
            contentTypes: Set<String> = ["application/json", "text/event-stream"],
            emptyStatuses: Set<Int> = [202, 204], onResponse: ResponseHandler? = nil) async throws -> WebSourceHTTPDecoder.Response {
    do {
      let checked = try MCPConnectionPolicy.endpoint(endpoint.absoluteString)
      guard let host = checked.host else { throw MCPClientError.invalidURL }
      try Task.checkCancellation()
      let addresses = try await resolve(host)
      try Task.checkCancellation()
      let request = try WebSourceRequest(url: checked, addresses: addresses, body: body, headers: headers)
      let decoder = WebSourceHTTPDecoder(maximumBodyBytes: maximumResponseBytes, contentTypes: contentTypes,
        successfulStatuses: 200..<300, emptyStatuses: emptyStatuses, additionalHeaders: ["mcp-session-id"])
      let response = try await transfer(request, decoder, onResponse)
      try Task.checkCancellation()
      guard (200..<300).contains(response.status) else { throw ExternalToolFailure.http(response.status) }
      return response
    } catch WebSourceFailure.timeout { throw MCPClientError.timeout }
    catch WebSourceFailure.unsafeAddress { throw MCPClientError.invalidURL }
    catch is WebSourceFailure { throw MCPClientError.malformed }
  }
}
