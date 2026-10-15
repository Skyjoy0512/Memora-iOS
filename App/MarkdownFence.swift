import Foundation

struct MarkdownFence {
  var character: Character
  var count: Int
  var language: String

  init?(_ line: String) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
    let count = trimmed.prefix { $0 == first }.count
    guard count >= 3 else { return nil }
    self.character = first
    self.count = count
    language = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
    guard first != "`" || !language.contains("`") else { return nil }
  }

  func closes(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let run = trimmed.prefix { $0 == character }.count
    return run >= count && trimmed.dropFirst(run).isEmpty
  }
}
