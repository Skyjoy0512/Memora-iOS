import Foundation

/// Each redirect gets a new validated URL and DNS answer. The transport accepts
/// only a numeric public endpoint, never a hostname it could resolve again.
struct WebSourceRequest: Sendable {
  private(set) var url: URL
  private(set) var host: String
  private(set) var address: String
  private(set) var bytes: Data

  init(url: URL, addresses: [String], body: Data? = nil, headers: [String: String] = [:]) throws {
    let checked = try Self.checkedURL(url)
    guard !addresses.isEmpty, addresses.count <= 64,
          addresses.allSatisfy(MCPPublicAddressPolicy.isPublic), let address = addresses.first(where: { !$0.contains(":") }) ?? addresses.first,
          let components = URLComponents(url: checked, resolvingAgainstBaseURL: false),
          let host = components.host else { throw WebSourceFailure.unsafeAddress }
    let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    let target = path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    guard target.utf8.allSatisfy({ (33...126).contains($0) }) else { throw WebSourceFailure.unsafeAddress }
    // Callers cannot override framing, the validated Host, or connection policy.
    var allowed = Set(["accept", "content-type", "authorization", "mcp-protocol-version", "mcp-session-id"])
    let githubHeaders = ["x-mcp-toolsets": "issues,pull_requests", "x-mcp-readonly": "true"]
    if checked.absoluteString == "https://api.githubcopilot.com/mcp/readonly", body != nil {
      allowed.formUnion(githubHeaders.keys)
    }
    var fields: [String: String] = [:]
    for (name, value) in headers {
      let key = name.lowercased()
      guard allowed.contains(key), fields[key] == nil, value.utf8.count <= 8_192,
            value.utf8.allSatisfy({ (32...126).contains($0) }) else { throw WebSourceFailure.unsafeAddress }
      if let expected = githubHeaders[key], value != expected { throw WebSourceFailure.unsafeAddress }
      fields[key] = value
    }
    guard body?.count ?? 0 <= 64 * 1024 else { throw WebSourceFailure.tooLarge }
    fields["accept"] = fields["accept"] ?? "text/html, application/xhtml+xml, text/plain, application/pdf"
    var head = "\(body == nil ? "GET" : "POST") \(target) HTTP/1.1\r\nHost: \(host)\r\nAccept-Encoding: identity\r\nUser-Agent: MemoraSource/1.0\r\nConnection: close\r\n"
    for key in fields.keys.sorted() { head += "\(key): \(fields[key]!)\r\n" }
    if let body { head += "Content-Length: \(body.count)\r\n" }
    guard head.utf8.count <= 16 * 1024 else { throw WebSourceFailure.tooLarge }
    self.url = checked; self.host = host; self.address = address
    bytes = Data((head + "\r\n").utf8) + (body ?? Data())
  }

  static func checkedURL(_ url: URL) throws -> URL {
    guard url.absoluteString.utf8.count <= 8_192,
          var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
          parts.port == nil || parts.port == 443, let host = parts.host,
          ProjectSourceURL.isPublicHostname(host.lowercased()),
          !url.absoluteString.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
      throw WebSourceFailure.unsafeAddress
    }
    parts.host = host.lowercased()
    parts.scheme = "https"
    parts.fragment = nil
    guard let checked = parts.url else { throw WebSourceFailure.unsafeAddress }
    return checked
  }
}
