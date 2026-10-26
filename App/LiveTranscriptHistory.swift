import Foundation

/// Display-only history; the AAC file and the final transcript are independent.
struct LiveTranscriptHistory {
  struct Line: Identifiable {
    var id: Int
    var text: String
  }
  static let maximumLines = 200
  static let maximumCharactersPerLine = 2_000
  static let maximumUTF8BytesPerLine = 8_192
  private(set) var lines: [Line] = []
  private(set) var totalLines = 0
  private(set) var hasTrimmedHistory = false

  mutating func append(_ text: String) {
    guard !text.isEmpty else { return }
    let bounded = Self.boundedText(text)
    hasTrimmedHistory = hasTrimmedHistory || bounded != text
    lines.append(Line(id: totalLines, text: bounded))
    totalLines += 1
    if lines.count > Self.maximumLines {
      lines.removeFirst(lines.count - Self.maximumLines)
      hasTrimmedHistory = true
    }
  }

  static func boundedText(_ text: String) -> String {
    if text.utf8.count <= maximumCharactersPerLine { return text }
    let bytes = String(decoding: text.utf8.suffix(maximumUTF8BytesPerLine), as: UTF8.self)
    return String(bytes.suffix(maximumCharactersPerLine))
  }
}
