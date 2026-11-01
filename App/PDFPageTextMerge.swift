import Foundation

enum PDFPageTextMerge {
  static func merge(digitalText: String, recognizedLines: [String]) -> String {
    let original = digitalText.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts = original.isEmpty ? [] : [original]
    var evidence = EvidenceIndex()
    evidence.append(tokens(original))
    for line in recognizedLines {
      let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
      let words = tokens(text)
      guard !words.isEmpty, !evidence.contains(words) else { continue }
      parts.append(text)
      evidence.append(words)
    }
    return parts.joined(separator: "\n")
  }

  // Whitespace may differ between PDF text and OCR. Everything else, including
  // punctuation and Unicode spelling, must match byte for byte before removal.
  private static func tokens(_ text: String) -> [Data] {
    text.split(whereSeparator: \.isWhitespace).map { Data($0.utf8) }
  }

  private struct EvidenceIndex {
    var words: [Data] = []
    var positions: [Data: [Int]] = [:]

    mutating func append(_ tokens: [Data]) {
      for token in tokens {
        positions[token, default: []].append(words.count)
        words.append(token)
      }
    }

    func contains(_ candidate: [Data]) -> Bool {
      guard let first = candidate.first, let starts = positions[first], candidate.count <= words.count else { return false }
      if candidate.count == 1 { return true }
      // Repeated words in a damaged page must not turn a long OCR line into a
      // quadratic series of prefix comparisons.
      if starts.count > 100_000 / candidate.count { return containsUsingPrefixTable(candidate) }
      for start in starts where start <= words.count - candidate.count {
        var offset = 0
        while offset < candidate.count, words[start + offset] == candidate[offset] { offset += 1 }
        if offset == candidate.count { return true }
      }
      return false
    }

    private func containsUsingPrefixTable(_ candidate: [Data]) -> Bool {
      var table = [Int](repeating: 0, count: candidate.count)
      var matched = 0
      for index in 1..<candidate.count {
        while matched > 0, candidate[index] != candidate[matched] { matched = table[matched - 1] }
        if candidate[index] == candidate[matched] { matched += 1 }
        table[index] = matched
      }
      matched = 0
      for word in words {
        while matched > 0, word != candidate[matched] { matched = table[matched - 1] }
        if word == candidate[matched] { matched += 1 }
        if matched == candidate.count { return true }
      }
      return false
    }
  }
}
