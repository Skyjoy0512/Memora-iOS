import Foundation

struct WebSourceFetcher: Sendable {
  var resolve: @Sendable (String) async throws -> [String] = { try await MCPPublicAddressPolicy.validatedAddresses(for: $0) }
  var transfer: @Sendable (WebSourceRequest) async throws -> WebSourceHTTPDecoder.Response = { try await PinnedHTTPSConnection.fetch($0) }

  struct Result: Sendable {
    var finalURL: URL
    var fetchedAt: Date
    var content: WebSourceTextExtraction.Result
  }

  func fetch(_ url: URL) async throws -> Result {
    try await withThrowingTaskGroup(of: Result.self) { group in
      group.addTask { try await fetchHops(url) }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw WebSourceFailure.timeout
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else { throw WebSourceFailure.network }
      return result
    }
  }

  private func fetchHops(_ original: URL) async throws -> Result {
    var url = original
    var visited: Set<URL> = []
    for _ in 0..<4 {
      try Task.checkCancellation()
      let checked = try WebSourceRequest.checkedURL(url)
      guard visited.insert(checked).inserted, let host = checked.host else { throw WebSourceFailure.redirects }
      let addresses: [String]
      do { addresses = try await resolve(host) }
      catch is CancellationError { throw CancellationError() }
      catch { throw WebSourceFailure.unsafeAddress }
      let request = try WebSourceRequest(url: checked, addresses: addresses)
      let response = try await transfer(request)
      try Task.checkCancellation()
      if [301, 302, 303, 307, 308].contains(response.status) {
        guard let location = response.headers["location"], location.utf8.count <= 8_192,
              !location.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let next = URL(string: location, relativeTo: checked)?.absoluteURL else { throw WebSourceFailure.invalidResponse }
        url = next; continue
      }
      guard response.status == 200 else { throw WebSourceFailure.status(response.status) }
      let content = try WebSourceTextExtraction.read(response.body, contentType: response.headers["content-type"] ?? "")
      return Result(finalURL: checked, fetchedAt: .now, content: content)
    }
    throw WebSourceFailure.redirects
  }
}
