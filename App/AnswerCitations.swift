import Foundation

/// Turns 【資料n】 markers in an answer into links to the records really sent
/// as 資料n. A number the answer was not given is dropped, so a citation can
/// never point at something the AI did not read.
enum AnswerCitations {
  static let scheme = "memora-cite"
  private static let pattern = /【資料(\d+)】/

  /// Whether the answer cites any record it was given.
  static func hasCitations(_ text: String, sources: [AIChatSource]) -> Bool {
    text.matches(of: pattern).contains { match in
      Int(match.output.1).map { $0 > 0 && $0 <= sources.count } ?? false
    }
  }

  /// The answer with valid markers as inline links and the rest removed.
  static func linked(_ text: String, sources: [AIChatSource]) -> String {
    text.replacing(pattern) { match in
      guard let number = Int(match.output.1), number > 0, number <= sources.count else { return "" }
      let title = sources[number - 1].title.replacingOccurrences(of: "]", with: "）")
      return " [↗\(title)](\(scheme)://\(number))"
    }
  }

  /// The answer with every marker removed, for the word-by-word reveal.
  static func stripped(_ text: String) -> String {
    text.replacing(pattern) { _ in "" }
  }

  static func saved(_ text: String, sources: [AIChatSource]) -> String {
    text.replacing(pattern) { match in
      guard let number = Int(match.output.1), number > 0, number <= sources.count,
            let url = MeetingLink.url(for: sources[number - 1].meetingID) else { return "" }
      return "[資料\(number)](\(url.absoluteString))"
    }
  }

  /// The record a citation link points at.
  static func source(for url: URL, in sources: [AIChatSource]) -> AIChatSource? {
    guard url.scheme == scheme, let number = Int(url.host() ?? ""), number > 0, number <= sources.count else {
      return nil
    }
    return sources[number - 1]
  }
}
