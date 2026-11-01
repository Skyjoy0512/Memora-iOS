import Foundation

enum SubtitleText {
  static func blocks(_ text: String) -> [ProjectSourceText] {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
    var result: [ProjectSourceText] = []
    var time: TimeInterval?
    var content: [String] = []
    var inHeader = true
    func flush() {
      result += SourceTextChunks.split(content.joined(separator: "\n"), time: time)
      content = []
    }
    for line in lines {
      if line.contains("-->") {
        flush()
        time = timestamp(String(line.components(separatedBy: "-->")[0]))
        inHeader = false
      } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
        flush(); time = nil; inHeader = true
      } else if !inHeader {
        content.append(line)
      }
    }
    flush()
    // Plain transcripts have no verified timeline.
    return result.isEmpty ? SourceTextChunks.split(text) : result
  }

  static func timestamp(_ value: String) -> TimeInterval? {
    let parts = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
      .split(separator: ":").compactMap { Double($0) }
    guard (2...3).contains(parts.count), parts.allSatisfy({ $0.isFinite && $0 >= 0 }),
          parts.last! < 60, parts[parts.count - 2] < 60 else { return nil }
    let result = parts.reduce(0) { $0 * 60 + $1 }
    return result.isFinite && result <= 7 * 24 * 60 * 60 ? result : nil
  }
}
