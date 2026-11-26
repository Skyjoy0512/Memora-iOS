import Foundation

/// A supported direct invitation. Only a provider adapter should read the URL.
struct MeetingBotTarget: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  enum Platform: String, Hashable, Sendable {
    case googleMeet, microsoftTeams
  }

  let platform: Platform
  let joinURL: URL

  var description: String { "MeetingBotTarget(\(platform.rawValue))" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: ["platform": platform]) }

  init?(_ input: String) {
    guard input.utf8.count <= 4_096, input.utf8.allSatisfy({ (33...126).contains($0) }),
          !input.contains("\\"), let original = URLComponents(string: input),
          original.scheme?.lowercased() == "https", original.user == nil, original.password == nil,
          original.port == nil || original.port == 443, original.fragment == nil,
          let host = original.percentEncodedHost?.lowercased() else { return nil }
    let path = original.percentEncodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    var canonical = URLComponents()
    canonical.scheme = "https"
    canonical.host = host

    switch host {
    case "meet.google.com":
      guard path.count == 1, let code = path.first, Self.isMeetCode(code) else { return nil }
      platform = .googleMeet
      // Meet's documented meeting URI consists of the code. Account-selection
      // and other invitation parameters do not belong in the provider request.
      canonical.path = "/" + code.lowercased()
    case "teams.microsoft.com":
      platform = .microsoftTeams
      if path.count == 2, path[0] == "meet", Self.isDigits(path[1]) {
        guard let items = original.queryItems, items.count == 1, items[0].name == "p",
              let passcode = items[0].value, Self.isIdentifier(passcode[...], limit: 128) else { return nil }
        canonical.path = "/meet/" + path[1]
        canonical.queryItems = [.init(name: "p", value: passcode)]
      } else {
        guard path.count == 4, path[0] == "l", path[1] == "meetup-join", Self.isDigits(path[3]),
              let thread = path[2].removingPercentEncoding, Self.isTeamsThread(thread) else { return nil }
        canonical.percentEncodedPath = "/l/meetup-join/" +
          thread.replacingOccurrences(of: ":", with: "%3A").replacingOccurrences(of: "@", with: "%40") +
          "/" + path[3]
        if original.percentEncodedQuery != nil {
          guard let context = Self.teamsContext(original.queryItems) else { return nil }
          canonical.queryItems = [.init(name: "context", value: context)]
        }
      }
    default:
      return nil
    }
    guard let url = canonical.url else { return nil }
    joinURL = url
  }

  private static func isMeetCode(_ value: Substring) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    return value.utf8.count <= 128 && parts.count == 3 && parts.allSatisfy {
      !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) }
    }
  }

  private static func isDigits(_ value: Substring) -> Bool {
    !value.isEmpty && value.utf8.count <= 20 && value.utf8.allSatisfy { (48...57).contains($0) }
  }

  private static func isIdentifier(_ value: Substring, limit: Int) -> Bool {
    !value.isEmpty && value.utf8.count <= limit && value.utf8.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
    }
  }

  private static func isTeamsThread(_ value: String) -> Bool {
    let prefix = "19:meeting_"
    guard value.hasPrefix(prefix),
          let suffix = ["@thread.v2", "@thread.skype"].first(where: value.hasSuffix),
          value.count > prefix.count + suffix.count else { return false }
    return isIdentifier(value.dropFirst(prefix.count).dropLast(suffix.count), limit: 256)
  }

  private static func teamsContext(_ items: [URLQueryItem]?) -> String? {
    guard let items, items.count == 1, items[0].name == "context", let raw = items[0].value,
          let context = try? JSONDecoder().decode([String: UUID].self, from: Data(raw.utf8)),
          context["Tid"] != nil, Set(context.keys).isSubset(of: ["Tid", "Oid"]) else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let encoded = try? encoder.encode(context) else { return nil }
    return String(decoding: encoded, as: UTF8.self)
  }
}
