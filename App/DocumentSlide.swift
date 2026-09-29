import Foundation

/// One slide of a slide document: a heading, its points and speaker notes.
struct DocumentSlide: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var title: String
  var bullets: [String]
  var notes = ""

  /// A slide with a heading and nothing under it is drawn as a title slide.
  var isTitleSlide: Bool {
    bullets.isEmpty
  }
}

extension DocumentSlide {
  /// The slides as plain text, so they can be edited in one text field:
  /// `# ` starts a slide, `- ` adds a point and `> ` a line of notes.
  static func outline(of slides: [DocumentSlide]) -> String {
    slides
      .map { slide in
        var lines = ["# \(slide.title)"]
        lines += slide.bullets.map { "- \($0)" }
        lines += slide.notes
          .split(separator: "\n", omittingEmptySubsequences: false)
          .filter { !$0.isEmpty }
          .map { "> \($0)" }
        return lines.joined(separator: "\n")
      }
      .joined(separator: "\n\n")
  }

  /// Reads the text `outline(of:)` writes. A line before the first heading
  /// starts an untitled slide rather than being dropped.
  static func slides(fromOutline outline: String) -> [DocumentSlide] {
    var slides: [DocumentSlide] = []
    for rawLine in outline.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("#") {
        let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        slides.append(DocumentSlide(title: title, bullets: []))
        continue
      }
      if slides.isEmpty {
        slides.append(DocumentSlide(title: "", bullets: []))
      }
      if line.hasPrefix(">") {
        let note = line.dropFirst().trimmingCharacters(in: .whitespaces)
        let existing = slides[slides.count - 1].notes
        slides[slides.count - 1].notes = existing.isEmpty ? note : existing + "\n" + note
      } else {
        let bullet = line.hasPrefix("-") || line.hasPrefix("・") || line.hasPrefix("*")
          ? line.dropFirst().trimmingCharacters(in: .whitespaces)
          : line
        slides[slides.count - 1].bullets.append(bullet)
      }
    }
    return slides
  }
}
