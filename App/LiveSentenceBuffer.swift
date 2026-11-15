import Foundation

// Adapted from Volocal's SentenceBuffer (MIT). See Resources/Volocal-LICENSE.txt.
struct LiveSentenceBuffer {
  private var buffer = ""
  private let maximumCharacters = 200

  mutating func append(_ text: String) -> [String] {
    buffer += text
    var sentences: [String] = []
    while let boundary = boundaryIndex() {
      let end = buffer.index(after: boundary)
      let sentence = String(buffer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !sentence.isEmpty { sentences.append(contentsOf: bounded(sentence)) }
      buffer = String(buffer[end...]).trimmingCharacters(in: .whitespaces)
    }
    while buffer.count > maximumCharacters {
      let limit = buffer.index(buffer.startIndex, offsetBy: maximumCharacters)
      let end = buffer[..<limit].lastIndex(where: { $0.isWhitespace }) ?? limit
      sentences.append(String(buffer[..<end]))
      buffer = String(buffer[end...]).trimmingCharacters(in: .whitespaces)
    }
    return sentences
  }

  mutating func flush() -> [String] {
    defer { buffer = "" }
    let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    return bounded(remaining)
  }

  mutating func reset() { buffer = "" }

  private func bounded(_ text: String) -> [String] {
    var remaining = text
    var result: [String] = []
    while remaining.count > maximumCharacters {
      let limit = remaining.index(remaining.startIndex, offsetBy: maximumCharacters)
      let space = remaining[..<limit].lastIndex(where: { $0.isWhitespace })
      let end = space.flatMap { $0 == remaining.startIndex ? nil : $0 } ?? limit
      result.append(String(remaining[..<end]))
      remaining = String(remaining[end...]).trimmingCharacters(in: .whitespaces)
    }
    if !remaining.isEmpty { result.append(remaining) }
    return result
  }

  private func boundaryIndex() -> String.Index? {
    for index in buffer.indices {
      let character = buffer[index]
      if "。！？".contains(character) { return index }
      let next = buffer.index(after: index)
      guard next < buffer.endIndex else { continue }
      if "!?;:".contains(character), buffer[next].isWhitespace { return index }
      if character == ".", buffer[next].isWhitespace {
        let following = buffer[next...].first(where: { !$0.isWhitespace })
        if following?.isUppercase == true { return index }
      }
    }
    return nil
  }
}
