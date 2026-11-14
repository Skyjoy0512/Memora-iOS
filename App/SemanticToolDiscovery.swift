import Foundation

/// Local lexical retrieval keeps external schemas within the existing budget.
/// Candidates have already passed connection review; a score is never a grant.
enum SemanticToolDiscovery {
  struct Candidate {
    var id: String
    var name: String
    var summary: String
    var schemaBytes: Int
    var isAvailable = true
    var isEnabled = true
  }

  static func select(_ candidates: [Candidate], request: String, explicit: Bool,
                     limit: Int = 16, byteLimit: Int = 24 * 1024) -> [String] {
    let terms: Set<String> = tokens(expanded(request))
    var ranked: [RankedCandidate] = []
    for candidate in candidates {
      guard candidate.isAvailable, candidate.isEnabled, candidate.schemaBytes >= 0 else { continue }
      let name: String = normalized(candidate.name)
      let summary: String = normalized(candidate.summary)
      var score: Int = 0
      for term: String in terms {
        if name.range(of: term) != nil { score += 4 }
        if summary.range(of: term) != nil { score += 1 }
      }
      if explicit || request.isEmpty || score > 0 { ranked.append(RankedCandidate(candidate: candidate, score: score)) }
    }
    ranked.sort { left, right in
      if left.score != right.score { return left.score > right.score }
      return left.candidate.id < right.candidate.id
    }
    var selected: [String] = []
    var bytes = 0
    for match in ranked where selected.count < max(0, limit) {
      let candidate = match.candidate
      guard !selected.contains(candidate.id), candidate.schemaBytes <= max(0, byteLimit) - bytes else { continue }
      selected.append(candidate.id)
      bytes += candidate.schemaBytes
    }
    return selected
  }

  private struct RankedCandidate {
    var candidate: Candidate
    var score: Int
  }

  private static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func tokens(_ text: String) -> Set<String> {
    var result: Set<String> = []
    for word in normalized(String(text.prefix(4_000))).components(separatedBy: CharacterSet.alphanumerics.inverted) where word.count > 1 {
      result.insert(word)
      if word.unicodeScalars.contains(where: { $0.value > 0x3000 }) {
        let characters = Array(word)
        for index in 0..<(characters.count - 1) { result.insert(String(characters[index...index + 1])) }
      }
    }
    return result
  }

  private static func expanded(_ request: String) -> String {
    let aliases = [("メール", " email mail gmail"), ("予定", " calendar event"), ("カレンダー", " calendar"),
      ("タスク", " task todo"), ("資料", " document file"), ("議事録", " meeting notes notion"),
      ("コード", " code github repository"), ("プルリクエスト", " pull request github"),
      ("課題", " issue linear"), ("イシュー", " issue"), ("ギットハブ", " github"), ("リニア", " linear")]
    return String(request.prefix(3_500)) + aliases.filter { request.localizedCaseInsensitiveContains($0.0) }.map(\.1).joined()
  }
}
