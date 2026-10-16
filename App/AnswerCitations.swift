import Foundation

/// Turns 【資料n】 markers in an answer into links to the records really sent
/// as 資料n. A number the answer was not given is dropped, so a citation can
/// never point at something the AI did not read.
enum AnswerCitations {
  static let scheme = "memora-cite"
  private static let pattern = /【資料(\d+)】/

  /// Whether the answer cites any record it was given.
  static func hasCitations(_ text: String, sources: [AIChatSource], allowedTargets: Set<ArtifactSourceTarget>? = nil) -> Bool {
    text.matches(of: pattern).contains { match in
      guard let number = Int(match.output.1), number > 0, number <= sources.count else { return false }
      return allowedTargets?.contains(.record(.meeting(sources[number - 1].meetingID))) ?? true
    } || !AnswerSourceCitation.citedTargets(in: text, allowed: allowedTargets ?? []).isEmpty
  }

  /// The answer with valid markers as inline links and the rest removed.
  static func linked(_ text: String, sources: [AIChatSource], allowedTargets: Set<ArtifactSourceTarget>? = nil) -> String {
    let linked = text.replacing(pattern) { match in
      guard let number = Int(match.output.1), number > 0, number <= sources.count else { return "" }
      guard allowedTargets?.contains(.record(.meeting(sources[number - 1].meetingID))) ?? true else { return "" }
      let title = escapeLabel(sources[number - 1].title)
      return " [↗\(title)](\(scheme)://\(number))"
    }
    return AnswerSourceCitation.linked(linked, allowed: allowedTargets ?? [])
  }

  /// The answer with every marker removed, for the word-by-word reveal.
  static func stripped(_ text: String) -> String {
    AnswerSourceCitation.stripped(text.replacing(pattern) { _ in "" })
  }

  static func saved(_ text: String, sources: [AIChatSource], allowedTargets: Set<ArtifactSourceTarget>? = nil) -> String {
    let saved = text.replacing(pattern) { match in
      guard let number = Int(match.output.1), number > 0, number <= sources.count,
            allowedTargets?.contains(.record(.meeting(sources[number - 1].meetingID))) ?? true,
            let url = MeetingLink.url(for: sources[number - 1].meetingID) else { return "" }
      return "[資料\(number)](\(url.absoluteString))"
    }
    return AnswerSourceCitation.linked(saved, allowed: allowedTargets ?? [])
  }

  /// The record a citation link points at.
  static func source(for url: URL, in sources: [AIChatSource]) -> AIChatSource? {
    guard url.scheme == scheme, let number = Int(url.host() ?? ""), number > 0, number <= sources.count,
          url.absoluteString == "\(scheme)://\(number)" else {
      return nil
    }
    return sources[number - 1]
  }

  static func escapeLabel(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
      .reduce(into: "") { result, character in
        if "\\[]*_`()".contains(character) { result.append("\\") }
        result.append(character)
      }
  }
}
