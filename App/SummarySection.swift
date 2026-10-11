import Foundation

struct SummarySection: Identifiable, Hashable, Codable {
  var id: UUID = UUID()
  var title: String
  var content: String
  var order: Int
  var sourceReferences: [UUID] = []

  static func parse(_ markdown: String) -> [Self] {
    var result: [Self] = []
    var title: String?
    var lines: [String] = []
    func finish() {
      guard let title else { return }
      result.append(Self(title: title, content: lines.joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines), order: result.count))
    }
    for line in markdown.components(separatedBy: "\n") {
      if line.hasPrefix("## ") {
        finish()
        title = String(line.dropFirst(3))
        lines = []
      } else if title != nil {
        lines.append(line)
      }
    }
    finish()
    return result
  }
}
