import Foundation

enum SourceTextChunks {
  static func split(_ text: String, page: Int? = nil, time: TimeInterval? = nil) -> [ProjectSourceText] {
    var remaining = text[...]
    var blocks: [ProjectSourceText] = []
    while !remaining.isEmpty {
      let end = remaining.index(remaining.startIndex, offsetBy: 1_200, limitedBy: remaining.endIndex) ?? remaining.endIndex
      let value = String(remaining[..<end])
      if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        blocks.append(ProjectSourceText(text: value, page: page, time: time))
      }
      remaining = remaining[end...]
    }
    return blocks
  }
}
