import Foundation

enum MCPConnectionPolicy {
  static func endpoint(_ raw: String) throws -> URL {
    guard let original = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          original.query == nil, original.fragment == nil,
          let normalized = try? ProjectSourceURL.normalized(raw), normalized.kind == .web else { throw MCPClientError.invalidURL }
    return normalized.url
  }
  static func tokenIsValid(_ token: String?) -> Bool {
    guard let token else { return true }
    return token.utf8.count <= 8_192 && !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }
}
