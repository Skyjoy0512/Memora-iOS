import Foundation

/// Canonicalization is deliberately separate from permission to fetch: a
/// hostname still needs DNS and redirect validation at every network hop.
enum ProjectSourceURL {
  struct Link: Equatable {
    var url: URL
    var kind: ProjectSource.Kind
    var youtubeID: String?
  }

  enum InvalidLink: LocalizedError {
    case invalid
    var errorDescription: String? { "公開されたHTTPSリンクを入力してください。ローカルアドレスや認証情報付きのURLは保存できません。" }
  }

  static func normalized(_ input: String) throws -> Link {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.utf8.count <= 8_192,
          !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          var components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "https",
          components.user == nil, components.password == nil,
          components.port == nil || components.port == 443,
          let rawHost = components.host else { throw InvalidLink.invalid }
    let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard isPublicHostname(host) else { throw InvalidLink.invalid }
    components.scheme = "https"
    components.host = host
    components.port = nil
    components.fragment = nil
    if components.path.isEmpty { components.path = "/" }
    components.queryItems = components.queryItems?.filter {
      !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased())
    }.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
    if components.queryItems?.isEmpty == true { components.queryItems = nil }

    let youtubeHost = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"].contains(host)
    if youtubeHost {
      let id: String?
      if host == "youtu.be" {
        id = components.path.split(separator: "/").first.map(String.init)
      } else if components.path == "/watch" {
        id = components.queryItems?.first { $0.name == "v" }?.value
      } else {
        let parts = components.path.split(separator: "/")
        id = parts.count == 2 && ["shorts", "embed", "live"].contains(String(parts[0])) ? String(parts[1]) : nil
      }
      guard let id, id.utf8.count == 11, id.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
      }), let canonical = URL(string: "https://www.youtube.com/watch?v=\(id)") else { throw InvalidLink.invalid }
      return Link(url: canonical, kind: .youtube, youtubeID: id)
    }
    guard let url = components.url else { throw InvalidLink.invalid }
    return Link(url: url, kind: .web)
  }

  static func isPublicHostname(_ host: String) -> Bool {
    // Reject literal addresses entirely, including alternate IPv4 spellings,
    // mapped IPv6, and integer/octal/hex hosts that URL parsers may normalize.
    guard !host.contains(":"), host.contains("."), !host.hasSuffix(".local"),
          !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
          !host.hasSuffix(".home"), !host.hasSuffix(".lan") else { return false }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2, let suffix = labels.last,
          suffix.contains(where: { $0.isLetter }), !suffix.hasPrefix("0x") else { return false }
    return labels.allSatisfy { label in
      !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
      label.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
  }
}
