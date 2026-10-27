import Foundation

enum InlineURLDetector {
  /// Only committed editor text is passed here. No pasteboard access or network requests.
  static func urls(in text: String, isComposing: Bool = false) -> [URL] {
    guard !isComposing, text.utf8.count <= 500_000,
          let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
    var seen = Set<URL>()
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      guard let url = match.url, let canonical = try? ProjectSourceURL.normalized(url.absoluteString).url,
            seen.insert(canonical).inserted, seen.count <= 5 else { return nil }
      return canonical
    }
  }

  static func inserting(summary: String, title: String, url: URL, into text: String) -> String {
    let safeTitle = title.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    return text + (text.isEmpty ? "" : "\n\n") + "\(safeTitle)\n出典: \(url.absoluteString)\n\n\(summary)"
  }
}
