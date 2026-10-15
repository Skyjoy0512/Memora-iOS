import Foundation

/// Each redirect gets a new validated URL and DNS answer. The transport accepts
/// only a numeric public endpoint, never a hostname it could resolve again.
struct WebSourceRequest: Sendable {
  private(set) var url: URL
  private(set) var host: String
  private(set) var address: String
  private(set) var bytes: Data

  init(url: URL, addresses: [String]) throws {
    let checked = try Self.checkedURL(url)
    guard !addresses.isEmpty, addresses.count <= 64,
          addresses.allSatisfy(MCPPublicAddressPolicy.isPublic), let address = addresses.first(where: { !$0.contains(":") }) ?? addresses.first,
          let components = URLComponents(url: checked, resolvingAgainstBaseURL: false),
          let host = components.host else { throw WebSourceFailure.unsafeAddress }
    let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    let target = path + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    guard target.utf8.allSatisfy({ (33...126).contains($0) }) else { throw WebSourceFailure.unsafeAddress }
    self.url = checked; self.host = host; self.address = address
    bytes = Data("GET \(target) HTTP/1.1\r\nHost: \(host)\r\nAccept: text/html, application/xhtml+xml, text/plain\r\nAccept-Encoding: identity\r\nUser-Agent: MemoraSource/1.0\r\nConnection: close\r\n\r\n".utf8)
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
