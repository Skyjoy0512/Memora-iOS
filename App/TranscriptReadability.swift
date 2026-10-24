import Foundation

/// A reversible reading projection, never a replacement for transcript evidence.
enum TranscriptReadability {
  private static let fillers = ["えーっと", "ええっと", "えーと", "ええと", "えっと", "あのー", "あのう", "えー", "um", "uh", "erm"]
  private static let separators = CharacterSet(charactersIn: " 、，,。\t")

  static func cleaned(_ source: String) -> String {
    let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    return normalized.components(separatedBy: "\n").map { line in
      let original = line.trimmingCharacters(in: .whitespaces)
      var value = original
      // Only unquoted, clearly delimited utterance starts are safe to remove.
      // Do not touch あの/その/はい/多分, in-sentence repairs, names or numbers.
      for _ in 0..<12 {
        guard let filler = fillers.first(where: { word in
          let prefix = String(value.prefix(word.count))
          // All-capital English abbreviations may be names, not hesitation.
          if word.first?.isASCII == true && prefix == word.uppercased() { return false }
          return prefix.lowercased() == word &&
            value.dropFirst(word.count).unicodeScalars.first.map(separators.contains) == true
        }) else { break }
        let next = String(value.dropFirst(filler.count).drop { character in
          character.unicodeScalars.allSatisfy(separators.contains)
        })
        guard !next.isEmpty else { break }
        value = next
      }
      return value
    }.joined(separator: "\n")
  }
}
