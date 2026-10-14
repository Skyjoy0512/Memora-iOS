import Foundation

enum RelevantTextWindow {
  static func text(_ text: String, matching terms: [String], maximumCharacters: Int) -> String {
    let limit = min(max(maximumCharacters, 0), 24_000)
    guard text.count > limit else { return text }
    guard limit > 2 else { return String(text.prefix(limit)) }
    let candidates = terms.filter { !$0.isEmpty && $0.count <= 4_000 }.sorted {
      $0.count == $1.count ? $0 < $1 : $0.count > $1.count
    }
    guard let range = candidates.lazy.compactMap({ text.range(of: $0, options: .caseInsensitive) }).first else {
      return String(text.prefix(limit - 1)) + "…"
    }
    let bodyLimit = limit - 2
    let matchLength = text.distance(from: range.lowerBound, to: range.upperBound)
    let leading = min(bodyLimit / 3, max(0, bodyLimit - matchLength), text.distance(from: text.startIndex, to: range.lowerBound))
    let start = text.index(range.lowerBound, offsetBy: -leading)
    let end = text.index(start, offsetBy: bodyLimit, limitedBy: text.endIndex) ?? text.endIndex
    return (start == text.startIndex ? "" : "…") + String(text[start..<end]) + (end == text.endIndex ? "" : "…")
  }
}
